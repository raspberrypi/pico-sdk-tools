#!/usr/bin/env python3
"""
Install the Raspberry Pi Pico toolchains and tools into the same locations the
Pico VS Code extension uses (``~/.pico-sdk``), then write a ``.picorc`` that puts
them all on ``PATH`` and include it from the user's shell rc file.

Versions are resolved from ``versionBundles.json`` and ``supportedToolchains.ini``
-- the same inputs the VS Code extension uses -- and the pico-sdk-tools release
that publishes each asset is found through the GitHub API. Nothing about a
specific SDK version is hard-coded here, so new releases need no changes.

The platform is detected, or given explicitly with ``--platform`` -- which CI
should do, so the same invocation cannot drift with the runner image.

Needs Python 3.9 or newer and the standard library only. ``git`` is used to
clone the SDK; without it that step is skipped with a warning.

Examples:
  ./install_pico_tools.py 2.3.0
  ./install_pico_tools.py 2.3.0 --no-openocd --no-riscv-toolchain
  ./install_pico_tools.py 2.3.0 --platform linux_x64 --github-path --no-rc-include
"""

from __future__ import annotations

import argparse
import json
import os
import platform as platform_module
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.error
import urllib.request
import zipfile
from configparser import ConfigParser
from io import StringIO
from pathlib import Path

GITHUB_API = "https://api.github.com"
GITHUB_RAW = "https://raw.githubusercontent.com"
PICO_VSCODE_REPO = "raspberrypi/pico-vscode"
PICO_SDK_TOOLS_REPO = "raspberrypi/pico-sdk-tools"
PICO_SDK_REPO_URL = "https://github.com/raspberrypi/pico-sdk.git"

GITHUB_NINJA = "https://github.com/ninja-build/ninja"
GITHUB_CMAKE = "https://github.com/Kitware/CMake"

USER_AGENT = "install_pico_tools.py"

PLATFORMS = ("linux_x64", "linux_arm64", "darwin_x64", "darwin_arm64", "win32_x64")

# Asset suffix used by raspberrypi/pico-sdk-tools releases, e.g.
# picotool-2.3.0-aarch64-lin.tar.gz / pico-sdk-tools-2.3.0-mac.zip
TOOLS_ASSET_SUFFIX = {
    "linux_x64": "x86_64-lin.tar.gz",
    "linux_arm64": "aarch64-lin.tar.gz",
    "darwin_x64": "mac.zip",
    "darwin_arm64": "mac.zip",
    "win32_x64": "x64-win.zip",
}

NINJA_ASSET = {
    "linux_x64": "ninja-linux.zip",
    "linux_arm64": "ninja-linux-aarch64.zip",
    "darwin_x64": "ninja-mac.zip",
    "darwin_arm64": "ninja-mac.zip",
    "win32_x64": "ninja-win.zip",
}

CMAKE_ASSET = {
    "linux_x64": "cmake-{v}-linux-x86_64.tar.gz",
    "linux_arm64": "cmake-{v}-linux-aarch64.tar.gz",
    "darwin_x64": "cmake-{v}-macos-universal.tar.gz",
    "darwin_arm64": "cmake-{v}-macos-universal.tar.gz",
    "win32_x64": "cmake-{v}-windows-x86_64.zip",
}

# --no-<name> flags, in install order.
COMPONENTS = (
    "sdk",
    "arm-toolchain",
    "riscv-toolchain",
    "pico-sdk-tools",
    "picotool",
    "openocd",
    "cmake",
    "ninja",
)

# Files the SDK's CMakeLists look for, so a clone missing its submodules is
# recognised rather than half working.
SDK_SUBMODULE_MARKERS = (
    "lib/tinyusb/src/portable/raspberrypi/rp2040",
    "lib/cyw43-driver/src/cyw43.h",
    "lib/lwip/src/Filelists.cmake",
    "lib/btstack/src/bluetooth.h",
    "lib/mbedtls/library/aes.c",
)

PICORC_BEGIN = "# >>> pico-sdk-tools installer >>>"
PICORC_END = "# <<< pico-sdk-tools installer <<<"


# --------------------------------------------------------------------------
# fetching
# --------------------------------------------------------------------------


def fetch_url_text(url: str, timeout: int = 120) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8")


def download(url: str, dest: Path, chunk: int = 1 << 20) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=600) as resp:
        nread = 0
        with dest.open("wb") as out:
            while True:
                buf = resp.read(chunk)
                if not buf:
                    break
                out.write(buf)
                nread += len(buf)
    print(f"    downloaded {nread} bytes")


# --------------------------------------------------------------------------
# archive handling
# --------------------------------------------------------------------------


def _extract_zip(archive: Path, target: Path) -> None:
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            mode = info.external_attr >> 16
            out = zf.extract(info, target)
            if mode and stat.S_ISLNK(mode):
                # macOS/Linux zips can carry symlinks; recreate them
                link_target = Path(out).read_text()
                Path(out).unlink()
                os.symlink(link_target, out)
            elif mode:
                os.chmod(out, mode & 0o7777)


def _extract_tar(archive: Path, target: Path) -> None:
    with tarfile.open(archive, "r:*") as tf:
        if hasattr(tarfile, "data_filter"):  # Python >= 3.12
            tf.extractall(target, filter="tar")
        else:
            tf.extractall(target)


def flatten_single_dir(target: Path) -> None:
    """Mirror the extension's behaviour: if the archive unpacked to a single
    top-level directory, hoist its contents up one level."""
    entries = list(target.iterdir())
    if len(entries) != 1 or not entries[0].is_dir():
        return
    sub = entries[0]
    for item in list(sub.iterdir()):
        shutil.move(str(item), str(target / item.name))
    sub.rmdir()


def extract(archive: Path, target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    name = archive.name.lower()
    if name.endswith(".zip"):
        _extract_zip(archive, target)
    elif ".tar." in name or name.endswith(".tar"):
        _extract_tar(archive, target)
    else:
        raise RuntimeError(f"Unsupported archive type: {archive.name}")
    flatten_single_dir(target)


def archive_suffix(url: str) -> str:
    seg = url.rstrip("/").split("/")[-1].split("?")[0]
    lowered = seg.lower()
    for suffix in (".tar.gz", ".tar.xz", ".tar.bz2", ".tar", ".zip"):
        if lowered.endswith(suffix):
            return suffix
    return Path(seg).suffix


# --------------------------------------------------------------------------
# version resolution (versionBundles.json + supportedToolchains.ini)
# --------------------------------------------------------------------------


def detect_platform() -> str:
    """Best guess at the platform key for the machine this is running on.

    Deliberately strict: anything not recognised is an error telling the caller
    to pass --platform, rather than a guess that downloads the wrong binaries.
    """
    system = sys.platform
    machine = platform_module.machine().lower()

    if system == "win32":
        # There is no Arm build of the Windows tools; Arm64 runs the x64 one.
        if machine in ("amd64", "x86_64", "arm64", "aarch64"):
            return "win32_x64"
    elif system == "darwin":
        if machine in ("arm64", "aarch64"):
            return "darwin_arm64"
        if machine in ("x86_64", "amd64"):
            return "darwin_x64"
    elif system.startswith("linux"):
        if machine in ("x86_64", "amd64"):
            return "linux_x64"
        if machine in ("aarch64", "arm64"):
            return "linux_arm64"

    raise RuntimeError(
        f"Cannot tell which platform {system}/{machine or '?'} is. "
        f"Pass --platform with one of: {', '.join(PLATFORMS)}"
    )


def parse_toolchains_ini_text(text: str) -> ConfigParser:
    cp = ConfigParser()
    cp.read_file(StringIO(text))
    return cp


def merge_modifiers(bundle: dict, platform_key: str) -> dict:
    out = dict(bundle)
    for key, value in (bundle.get("modifiers") or {}).get(platform_key, {}).items():
        out[key] = value
    return out


# --------------------------------------------------------------------------
# GitHub API
# --------------------------------------------------------------------------


def github_api(path: str, token: str | None):
    """GET a GitHub API path and decode the JSON body."""
    headers = {"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{GITHUB_API}{path}", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 429) and not token:
            raise RuntimeError(
                f"GitHub API refused {path} (HTTP {exc.code}). The unauthenticated "
                "limit is 60 requests an hour; set GITHUB_TOKEN or pass "
                "--github-token to raise it."
            ) from exc
        raise RuntimeError(f"GitHub API request for {path} failed: {exc}") from exc


def latest_extension_data_version(token: str | None) -> str:
    """Newest version-metadata directory published by the Pico VS Code extension."""
    entries = github_api(f"/repos/{PICO_VSCODE_REPO}/contents/data", token)
    versions = []
    for entry in entries:
        name = entry.get("name", "")
        if entry.get("type") != "dir":
            continue
        parts = name.split(".")
        if parts and all(part.isdigit() for part in parts):
            versions.append((tuple(int(part) for part in parts), name))
    if not versions:
        raise RuntimeError(f"No data directories in {PICO_VSCODE_REPO}")
    return max(versions)[1]


def extension_data_url(version: str) -> str:
    """Where that version's metadata files live.

    Read from the repository, not the published site: the version number came
    from the repository, and the site can lag behind it after a release.
    """
    return f"{GITHUB_RAW}/{PICO_VSCODE_REPO}/main/data/{version}"


def fetch_releases(repo: str, token: str | None) -> list[dict]:
    """Every published release of a repository, newest first."""
    releases: list[dict] = []
    page = 1
    while True:
        batch = github_api(f"/repos/{repo}/releases?per_page=100&page={page}", token)
        if not batch:
            break
        releases.extend(r for r in batch if not r.get("draft"))
        if len(batch) < 100:
            break
        page += 1
    return releases


def find_release_asset(
    releases: list[dict],
    pattern: re.Pattern,
    description: str,
    tag: str | None = None,
) -> tuple[str, str, re.Match]:
    """Locate an asset in the newest release that publishes it.

    Releases come back newest first, so the first match is the most recent build.
    """
    for release in releases:
        if tag and release["tag_name"] != tag:
            continue
        for asset in release.get("assets", []):
            match = pattern.fullmatch(asset["name"])
            if match:
                return release["tag_name"], asset["browser_download_url"], match
    where = f"release {tag}" if tag else f"any {PICO_SDK_TOOLS_REPO} release"
    raise RuntimeError(f"No {description} asset in {where}")


# --------------------------------------------------------------------------
# shell rc generation
# --------------------------------------------------------------------------


def shell_path(path: str | Path, home: Path) -> str:
    """Double-quoted shell literal, using ${HOME} where possible."""
    text = path.as_posix() if isinstance(path, Path) else str(path)
    home_posix = home.as_posix()
    prefix = ""
    if text == home_posix:
        text = ""
        prefix = "${HOME}"
    elif text.startswith(home_posix + "/"):
        text = text[len(home_posix) + 1 :]
        prefix = "${HOME}/"
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("$", "\\$")
        .replace("`", "\\`")
    )
    return '"' + prefix + escaped + '"'


def write_picorc(
    picorc: Path,
    home: Path,
    path_entries: list[Path],
    env_vars: list[tuple[str, str | Path]],
    sdk_version: str,
    platform_key: str,
) -> None:
    lines = [
        "# Pico SDK tools environment.",
        "# Generated by install_pico_tools.py -- edits will be lost on re-run.",
        f"# SDK {sdk_version}, platform {platform_key}",
        "",
        "_picorc_prepend_path() {",
        '    [ -d "$1" ] || return 0',
        '    case ":${PATH}:" in',
        '        *":$1:"*) ;;',
        '        *) PATH="$1${PATH:+:${PATH}}" ;;',
        "    esac",
        "}",
        "",
    ]
    # Prepend in reverse so the resulting PATH order matches path_entries.
    for entry in reversed(path_entries):
        lines.append(f"_picorc_prepend_path {shell_path(entry, home)}")
    lines += [
        "",
        "export PATH",
        "unset -f _picorc_prepend_path",
        "",
    ]
    for name, value in env_vars:
        lines.append(f"export {name}={shell_path(value, home)}")
    lines.append("")

    picorc.parent.mkdir(parents=True, exist_ok=True)
    picorc.write_text("\n".join(lines), encoding="utf-8")


def include_from_rc(rc_file: Path, picorc: Path, home: Path) -> str:
    """Add (or refresh) the block that sources .picorc. Returns a status word."""
    block = "\n".join(
        [
            PICORC_BEGIN,
            "# Added by install_pico_tools.py",
            f"if [ -f {shell_path(picorc, home)} ]; then . {shell_path(picorc, home)}; fi",
            PICORC_END,
        ]
    )

    existing = rc_file.read_text(encoding="utf-8") if rc_file.is_file() else ""

    if PICORC_BEGIN in existing and PICORC_END in existing:
        start = existing.index(PICORC_BEGIN)
        end = existing.index(PICORC_END) + len(PICORC_END)
        updated = existing[:start] + block + existing[end:]
        if updated == existing:
            return "already up to date"
        rc_file.write_text(updated, encoding="utf-8")
        return "updated"

    prefix = existing
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    if prefix:
        prefix += "\n"
    rc_file.parent.mkdir(parents=True, exist_ok=True)
    rc_file.write_text(prefix + block + "\n", encoding="utf-8")
    return "added"


def write_github_env(
    path_entries: list[Path], env_vars: list[tuple[str, str | Path]]
) -> None:
    github_path = os.environ.get("GITHUB_PATH")
    github_env = os.environ.get("GITHUB_ENV")
    if not github_path or not github_env:
        print(
            "  --github-path given but GITHUB_PATH/GITHUB_ENV are not set; skipping",
            file=sys.stderr,
        )
        return
    with open(github_path, "a", encoding="utf-8") as handle:
        for entry in path_entries:
            handle.write(f"{entry}\n")
    with open(github_env, "a", encoding="utf-8") as handle:
        for name, value in env_vars:
            handle.write(f"{name}={value}\n")
    print(f"  exported {len(path_entries)} PATH entries via $GITHUB_PATH")
    print(f"  exported {len(env_vars)} variables via $GITHUB_ENV")


# --------------------------------------------------------------------------
# install
# --------------------------------------------------------------------------


def run_git(args: list[str], cwd: Path | None = None) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True)


def install_sdk(version: str, target: Path, force: bool, dry_run: bool) -> bool:
    """Clone the SDK at its tag and initialise submodules, as the extension does.

    A missing git is a warning, not an error: the tools are still worth having,
    and an SDK already sitting in place is fine to reuse.
    """
    print("pico-sdk:")
    print(f"  {PICO_SDK_REPO_URL} at {version}")
    print(f"  -> {target}")

    git = shutil.which("git")
    present = target.is_dir() and any(target.iterdir())

    if present and not force:
        missing = [m for m in SDK_SUBMODULE_MARKERS if not (target / m).exists()]
        if not missing:
            print("  already installed, skipping (use --force to reinstall)")
            return False
        if not git:
            print(
                f"Warning: {target} is missing submodules and git is not "
                "installed, so they cannot be initialised.",
                file=sys.stderr,
            )
            return False
        print(f"  already installed, initialising {len(missing)} missing submodules")
        # No --force: this recovers a clone made without submodules, and should
        # not throw away local changes in one that has them.
        if not dry_run:
            run_git(["submodule", "update", "--init", "--depth", "1"], cwd=target)
        return True

    if not git:
        print(
            "Warning: git is not installed and no SDK is present at "
            f"{target}, so the SDK was not cloned. Install git and re-run, or "
            "put the SDK there yourself.",
            file=sys.stderr,
        )
        return False

    if dry_run:
        print("  would clone and initialise submodules")
        return False

    if present:
        shutil.rmtree(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Shallow: only the tagged tree is needed to build, and the history is
    # most of the download.
    run_git(
        [
            "-c",
            "advice.detachedHead=false",
            "clone",
            "--depth",
            "1",
            "--branch",
            version,
            PICO_SDK_REPO_URL,
            str(target),
        ]
    )
    run_git(["submodule", "update", "--init", "--depth", "1"], cwd=target)
    print("  installed")
    return True


def install_archive(
    label: str,
    url: str,
    target: Path,
    cache_dir: Path,
    force: bool,
    dry_run: bool,
) -> bool:
    """Download and unpack into target. Returns True if anything was installed."""
    print(f"{label}:")
    print(f"  {url}")
    print(f"  -> {target}")

    if target.is_dir() and any(target.iterdir()):
        if not force:
            print("  already installed, skipping (use --force to reinstall)")
            return False
        shutil.rmtree(target)

    if dry_run:
        print("  would download and unpack")
        return False

    archive = cache_dir / (label.lower().replace(" ", "-") + archive_suffix(url))
    download(url, archive)
    extract(archive, target)
    archive.unlink(missing_ok=True)
    print("  installed")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Download the Pico toolchains and tools into ~/.pico-sdk and set up "
            "a .picorc that adds them to PATH."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("sdk_version", help="SDK version key, e.g. 2.3.0")
    parser.add_argument(
        "--platform",
        choices=PLATFORMS,
        help="Target platform key (default: detected from this machine)",
    )
    parser.add_argument(
        "--install-dir",
        type=Path,
        default=None,
        help="Where to install (default: ~/.pico-sdk, matching the VS Code extension)",
    )

    for component in COMPONENTS:
        parser.add_argument(
            f"--no-{component}",
            dest=f"skip_{component.replace('-', '_')}",
            action="store_true",
            help=f"Do not install {component}",
        )

    parser.add_argument(
        "--picorc",
        type=Path,
        default=None,
        help="Path to the generated rc fragment (default: ~/.picorc)",
    )
    parser.add_argument(
        "--no-picorc",
        action="store_true",
        help="Do not write the .picorc file",
    )
    parser.add_argument(
        "--rc-file",
        type=Path,
        default=None,
        help="Shell rc file to include .picorc from "
        "(default: ~/.zshrc on darwin_*, otherwise ~/.bashrc)",
    )
    parser.add_argument(
        "--no-rc-include",
        action="store_true",
        help="Write .picorc but do not modify the shell rc file",
    )
    parser.add_argument(
        "--github-path",
        action="store_true",
        help="Also export PATH entries and variables via $GITHUB_PATH / $GITHUB_ENV",
    )

    parser.add_argument(
        "--extension-data-url",
        metavar="URL",
        help="Base URL for versionBundles.json and supportedToolchains.ini "
        "(default: the newest data version published by the Pico VS Code "
        "extension, discovered through the GitHub API)",
    )
    parser.add_argument(
        "--github-token",
        metavar="TOKEN",
        help="Token for GitHub API requests (default: $GITHUB_TOKEN or $GH_TOKEN). "
        "Unauthenticated requests are limited to 60 an hour.",
    )
    parser.add_argument(
        "--bundles",
        type=Path,
        help="Use a local versionBundles.json instead of --extension-data-url",
    )
    parser.add_argument(
        "--toolchains-ini",
        type=Path,
        help="Use a local supportedToolchains.ini instead of --extension-data-url",
    )
    parser.add_argument(
        "--pico-sdk-tools-tag",
        metavar="TAG",
        help="Take pico-sdk-tools from this raspberrypi/pico-sdk-tools release instead "
        "of the newest one that publishes it",
    )
    parser.add_argument(
        "--picotool-tag",
        metavar="TAG",
        help="Take picotool from this raspberrypi/pico-sdk-tools release instead "
        "of the newest one that publishes it",
    )
    parser.add_argument(
        "--openocd-tag",
        metavar="TAG",
        help="Take OpenOCD from this raspberrypi/pico-sdk-tools release instead "
        "of the newest one that publishes it",
    )
    parser.add_argument(
        "--openocd-version",
        metavar="VERSION",
        help="Install this OpenOCD version (default: whichever one the newest "
        "pico-sdk-tools release publishes)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Reinstall components that are already present",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be downloaded, change nothing",
    )
    args = parser.parse_args()

    sdk_version = args.sdk_version.strip()
    try:
        platform_key = args.platform or detect_platform()
    except RuntimeError as exc:
        print(exc, file=sys.stderr)
        return 1
    home = Path.home()
    root = (args.install_dir or (home / ".pico-sdk")).expanduser().resolve()
    token = (
        args.github_token
        or os.environ.get("GITHUB_TOKEN")
        or os.environ.get("GH_TOKEN")
    )

    # ---- version metadata -------------------------------------------------
    try:
        if args.extension_data_url:
            base = args.extension_data_url.rstrip("/")
        elif args.bundles and args.toolchains_ini:
            base = ""  # both files are local, nothing to discover
        else:
            data_version = latest_extension_data_version(token)
            base = extension_data_url(data_version)
            print(f"Pico VS Code data version {data_version}")
    except (RuntimeError, OSError) as exc:
        print(f"Failed to find the Pico VS Code data version: {exc}", file=sys.stderr)
        return 1

    try:
        if args.bundles:
            bundles = json.loads(args.bundles.read_text(encoding="utf-8"))
        else:
            print(f"Using {base}/versionBundles.json")
            bundles = json.loads(fetch_url_text(f"{base}/versionBundles.json"))

        if args.toolchains_ini:
            ini = parse_toolchains_ini_text(
                args.toolchains_ini.read_text(encoding="utf-8")
            )
        else:
            print(f"Using {base}/supportedToolchains.ini")
            ini = parse_toolchains_ini_text(
                fetch_url_text(f"{base}/supportedToolchains.ini")
            )
    except (OSError, urllib.error.HTTPError) as exc:
        print(f"Failed to read version metadata: {exc}", file=sys.stderr)
        return 1

    if sdk_version not in bundles:
        print(
            f"Unknown SDK version {sdk_version!r}. Known: {', '.join(sorted(bundles))}",
            file=sys.stderr,
        )
        return 1

    bundle = merge_modifiers(bundles[sdk_version], platform_key)
    arm_key = bundle["toolchain"]
    riscv_key = bundle.get("riscvToolchain") or "NONE"
    picotool_version = bundle["picotool"]
    cmake_version = bundle["cmake"]
    ninja_version = bundle["ninja"]
    openocd_version = args.openocd_version

    riscv_url = ""
    if riscv_key.upper() != "NONE":
        riscv_url = ini.get(riscv_key, platform_key, fallback="")

    skip = {c: getattr(args, f"skip_{c.replace('-', '_')}") for c in COMPONENTS}
    if riscv_key.upper() == "NONE":
        skip["riscv-toolchain"] = True

    # ---- pico-sdk-tools release assets ------------------------------------
    suffix = TOOLS_ASSET_SUFFIX[platform_key]
    from_releases = ("pico-sdk-tools", "picotool", "openocd")
    assets: dict[str, tuple[str, str, re.Match]] = {}
    if any(not skip[c] for c in from_releases):
        try:
            releases = fetch_releases(PICO_SDK_TOOLS_REPO, token)
        except (RuntimeError, OSError) as exc:
            print(f"Failed to list {PICO_SDK_TOOLS_REPO} releases: {exc}", file=sys.stderr)
            return 1

        tools_name = f"pico-sdk-tools-{sdk_version}-{suffix}"
        picotool_name = f"picotool-{picotool_version}-{suffix}"
        # OpenOCD has no entry in versionBundles.json, so take its version
        # from the asset name.
        openocd_name = (
            f"openocd-{args.openocd_version}-{suffix}"
            if args.openocd_version
            else f"openocd-<version>-{suffix}"
        )
        wanted = {
            "pico-sdk-tools": (
                re.compile(re.escape(tools_name)),
                tools_name,
                args.pico_sdk_tools_tag,
            ),
            "picotool": (
                re.compile(re.escape(picotool_name)),
                picotool_name,
                args.picotool_tag,
            ),
            "openocd": (
                re.compile(
                    re.escape(openocd_name)
                    if args.openocd_version
                    else r"openocd-(?P<version>.+)-" + re.escape(suffix)
                ),
                openocd_name,
                args.openocd_tag,
            ),
        }
        for component, (pattern, description, tag) in wanted.items():
            if skip[component]:
                continue
            try:
                assets[component] = find_release_asset(
                    releases, pattern, description, tag
                )
            except RuntimeError as exc:
                print(f"{exc}", file=sys.stderr)
                return 1

    if "openocd" in assets:
        match = assets["openocd"][2]
        openocd_version = match.groupdict().get("version") or args.openocd_version
    else:
        openocd_version = args.openocd_version or "-"

    def summarise(label: str, version: str, component: str | None = None) -> None:
        release = f"   (release {assets[component][0]})" if component in assets else ""
        print(f"  {label:<16} {version:<12}{release}".rstrip())

    print()
    print(f"SDK {sdk_version}  platform {platform_key}")
    print(f"  install dir      {root}")
    summarise("pico-sdk", sdk_version)
    summarise("arm toolchain", arm_key)
    summarise("riscv toolchain", riscv_key)
    summarise("pioasm", sdk_version, "pico-sdk-tools")
    summarise("picotool", picotool_version, "picotool")
    summarise("openocd", openocd_version, "openocd")
    summarise("cmake", cmake_version)
    summarise("ninja", ninja_version)
    skipped = [c for c in COMPONENTS if skip[c]]
    if skipped:
        print(f"  skipping         {', '.join(skipped)}")
    print()

    cache_dir = root / ".download-cache"
    if not args.dry_run:
        cache_dir.mkdir(parents=True, exist_ok=True)

    sdk_dir = root / "sdk" / sdk_version
    tools_dir = root / "tools" / sdk_version
    picotool_dir = root / "picotool" / picotool_version
    openocd_dir = root / "openocd" / openocd_version
    cmake_dir = root / "cmake" / cmake_version
    ninja_dir = root / "ninja" / ninja_version
    arm_dir = root / "toolchain" / arm_key
    riscv_dir = root / "toolchain" / riscv_key

    try:
        # ---- SDK ------------------------------------------------------------
        if not skip["sdk"]:
            install_sdk(sdk_version, sdk_dir, args.force, args.dry_run)

        # ---- Arm toolchain ------------------------------------------------
        if not skip["arm-toolchain"]:
            if not ini.has_section(arm_key):
                print(f"No [{arm_key}] in supportedToolchains.ini", file=sys.stderr)
                return 1
            arm_url = ini.get(arm_key, platform_key, fallback="")
            if not arm_url:
                print(
                    f"No Arm toolchain URL for [{arm_key}] {platform_key}",
                    file=sys.stderr,
                )
                return 1
            install_archive(
                "Arm GCC", arm_url, arm_dir, cache_dir, args.force, args.dry_run
            )

        # ---- RISC-V toolchain ---------------------------------------------
        if not skip["riscv-toolchain"]:
            if not riscv_url:
                print(
                    f"No RISC-V toolchain URL for [{riscv_key}] {platform_key}",
                    file=sys.stderr,
                )
                return 1
            install_archive(
                "RISC-V GCC", riscv_url, riscv_dir, cache_dir, args.force, args.dry_run
            )

        # ---- pico-sdk-tools (pioasm) ---------------------------------------
        if not skip["pico-sdk-tools"]:
            install_archive(
                "pico-sdk-tools",
                assets["pico-sdk-tools"][1],
                tools_dir,
                cache_dir,
                args.force,
                args.dry_run,
            )

        # ---- picotool -------------------------------------------------------
        if not skip["picotool"]:
            install_archive(
                "picotool",
                assets["picotool"][1],
                picotool_dir,
                cache_dir,
                args.force,
                args.dry_run,
            )

        # ---- OpenOCD --------------------------------------------------------
        if not skip["openocd"]:
            installed = install_archive(
                "OpenOCD",
                assets["openocd"][1],
                openocd_dir,
                cache_dir,
                args.force,
                args.dry_run,
            )
            # The extension creates this alias so the same config works everywhere.
            alias = openocd_dir / "openocd.exe"
            if installed and platform_key != "win32_x64" and not alias.exists():
                try:
                    os.symlink(openocd_dir / "openocd", alias)
                except OSError as exc:
                    print(f"  could not create openocd.exe alias: {exc}")

        # ---- CMake ----------------------------------------------------------
        if not skip["cmake"]:
            asset = CMAKE_ASSET[platform_key].format(v=cmake_version.lstrip("v"))
            installed = install_archive(
                "CMake",
                f"{GITHUB_CMAKE}/releases/download/{cmake_version}/{asset}",
                cmake_dir,
                cache_dir,
                args.force,
                args.dry_run,
            )
            # macOS ships an app bundle; symlink bin/ so the path is uniform.
            app_bin = cmake_dir / "CMake.app" / "Contents" / "bin"
            if installed and app_bin.is_dir() and not (cmake_dir / "bin").exists():
                os.symlink(app_bin, cmake_dir / "bin", target_is_directory=True)

        # ---- Ninja ----------------------------------------------------------
        if not skip["ninja"]:
            install_archive(
                "ninja",
                f"{GITHUB_NINJA}/releases/download/{ninja_version}/"
                f"{NINJA_ASSET[platform_key]}",
                ninja_dir,
                cache_dir,
                args.force,
                args.dry_run,
            )
            ninja_bin = ninja_dir / "ninja"
            if ninja_bin.is_file():
                ninja_bin.chmod(ninja_bin.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except urllib.error.HTTPError as exc:
        print(f"  HTTP {exc.code}: {exc.reason}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"  git failed: {' '.join(exc.cmd)}", file=sys.stderr)
        return 1
    except (OSError, RuntimeError) as exc:
        print(f"  Error: {exc}", file=sys.stderr)
        return 1

    if not args.dry_run and cache_dir.is_dir() and not any(cache_dir.iterdir()):
        cache_dir.rmdir()

    # ---- environment ------------------------------------------------------
    path_entries: list[Path] = []
    env_vars: list[tuple[str, str | Path]] = []

    if not skip["picotool"]:
        path_entries.append(picotool_dir / "picotool")
        env_vars.append(("picotool_DIR", picotool_dir / "picotool"))
    if not skip["pico-sdk-tools"]:
        path_entries.append(tools_dir / "pioasm")
        env_vars.append(("pioasm_DIR", tools_dir / "pioasm"))
    if not skip["openocd"]:
        path_entries.append(openocd_dir)
        env_vars.append(("OPENOCD_SCRIPTS", openocd_dir / "scripts"))
    if not skip["arm-toolchain"]:
        path_entries.append(arm_dir / "bin")
        # Not PICO_TOOLCHAIN_PATH: pinning it to the Arm toolchain makes
        # every RISC-V configure warn before falling back to PATH, which finds
        # the right compiler by triple anyway.
        env_vars.append(("PICO_ARM_TOOLCHAIN_PATH", arm_dir))
    if not skip["riscv-toolchain"]:
        path_entries.append(riscv_dir / "bin")
        env_vars.append(("PICO_RISCV_TOOLCHAIN_PATH", riscv_dir))
    if not skip["cmake"]:
        path_entries.append(cmake_dir / "bin")
    if not skip["ninja"]:
        path_entries.append(ninja_dir)
        # CMake picks Unix Makefiles by default; ninja is what we just installed
        # and what the extension configures. A -G on the command line still wins.
        env_vars.append(("CMAKE_GENERATOR", "Ninja"))

    if sdk_dir.is_dir():
        env_vars.insert(0, ("PICO_SDK_PATH", sdk_dir))

    print()
    if args.dry_run:
        print("(dry run: nothing downloaded, no files written)")
        for entry in path_entries:
            print(f"  PATH += {entry}")
        for name, value in env_vars:
            print(f"  {name}={value}")
        return 0

    picorc = (args.picorc or (home / ".picorc")).expanduser()
    if not args.no_picorc:
        write_picorc(picorc, home, path_entries, env_vars, sdk_version, platform_key)
        print(f"Wrote {picorc}")

        if not args.no_rc_include:
            default_rc = ".zshrc" if platform_key.startswith("darwin") else ".bashrc"
            rc_file = (args.rc_file or (home / default_rc)).expanduser()
            status = include_from_rc(rc_file, picorc, home)
            print(f"Include block in {rc_file}: {status}")
            print(f"Run `source {picorc}` or open a new shell to pick up the tools.")

    if args.github_path:
        write_github_env(path_entries, env_vars)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
