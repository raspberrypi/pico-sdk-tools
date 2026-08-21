# Pico SDK tools installer

A single Python script that downloads the Raspberry Pi Pico toolchains and tools
into `~/.pico-sdk` - the same locations and layout the
[Pico VS Code extension](https://github.com/raspberrypi/pico-vscode) uses - then
writes a `picorc` alongside them that puts them all on `PATH`, and includes it
from your shell rc file.

It resolves versions from `versionBundles.json` and `supportedToolchains.ini`,
the same inputs the extension uses, so `2.3.0` gets you exactly the toolchain,
picotool, OpenOCD, CMake and ninja that the extension would install for SDK
2.3.0.

Because it installs to the extension's directories, a machine set up with this
script and a machine set up through VS Code end up with the same tools, and
neither will re-download what the other already fetched.

Nothing about a particular SDK version is written down in the script, so a new
SDK release needs no changes to it. See
[Version resolution](#version-resolution) for how that works.

## Quick start

Needs Python 3.9 or newer. To download and run it:

```bash
wget https://raw.githubusercontent.com/raspberrypi/pico-sdk-tools/main/installer/install_pico_tools.py
chmod +x install_pico_tools.py
./install_pico_tools.py 2.3.0
```

Then pick up the tools and check one works:

```bash
exec $SHELL          # or: source ~/.pico-sdk/picorc
picotool version
```

The platform is detected from the machine. Detection is deliberately strict -
anything it does not recognise is an error rather than a guess that downloads
the wrong binaries - so pass `--platform` for anything else, and in CI, where
pinning it stops the build drifting with the runner image:

| `--platform`   | Target                       | Detected from                |
| -------------- | ---------------------------- | ---------------------------- |
| `linux_x64`    | Linux x86-64                 | `linux` + `x86_64`/`amd64`   |
| `linux_arm64`  | Linux AArch64 (Raspberry Pi) | `linux` + `aarch64`/`arm64`  |
| `darwin_x64`   | macOS Intel                  | `darwin` + `x86_64`          |
| `darwin_arm64` | macOS Apple silicon          | `darwin` + `arm64`           |
| `win32_x64`    | Windows x64                  | `win32`, any architecture    |

There are no 32-bit builds, so 32-bit Arm Linux is one of the cases that errors
out.

## What gets installed where

Everything lands under `~/.pico-sdk` (override with `--install-dir`):

| Component        | Directory                          | Added to `PATH`                     |
| ---------------- | ---------------------------------- | ----------------------------------- |
| pico-sdk         | `sdk/<version>/`                   | -                                   |
| Arm GCC          | `toolchain/<key>/`                 | `toolchain/<key>/bin`               |
| RISC-V GCC       | `toolchain/<key>/`                 | `toolchain/<key>/bin`               |
| `pioasm`         | `tools/<sdk>/pioasm/`              | `tools/<sdk>/pioasm`                |
| `picotool`       | `picotool/<version>/picotool/`     | `picotool/<version>/picotool`       |
| OpenOCD          | `openocd/<version>/`               | `openocd/<version>`                 |
| CMake            | `cmake/<version>/`                 | `cmake/<version>/bin`               |
| ninja            | `ninja/<version>/`                 | `ninja/<version>`                   |

Arm GCC comes from Arm's download server; `pioasm`, `picotool`, OpenOCD and the
RISC-V toolchain come from
[raspberrypi/pico-sdk-tools](https://github.com/raspberrypi/pico-sdk-tools);
CMake and ninja come from their upstream releases. The SDK is a shallow
`git clone` at the matching tag followed by `git submodule update --init
--depth 1`, and sets `PICO_SDK_PATH`.

If git is not installed, the SDK is skipped with a warning and the rest still
installs. A clone that is already there is reused; if it is missing submodules
they are initialised in place, without discarding any local changes.

Components already present are left alone, so re-running is cheap. Use
`--force` to reinstall.

### Skipping components

Every component has a `--no-<component>` flag:

```bash
./install_pico_tools.py 2.3.0 --platform linux_x64 \
    --no-riscv-toolchain --no-openocd --no-cmake --no-ninja
```

Valid components: `sdk`, `arm-toolchain`, `riscv-toolchain`, `pico-sdk-tools`,
`picotool`, `openocd`, `cmake`, `ninja`. Skipped components are left out of
`picorc` too.

## Version resolution

Two API lookups, so the script does not need updating when a new SDK
version is released:

1. **Which versions belong to an SDK.** The Pico VS Code extension publishes one
   directory of version metadata per data version. The script asks the GitHub
   API for the newest of those in
   [`raspberrypi/pico-vscode`](https://github.com/raspberrypi/pico-vscode), then
   reads `versionBundles.json` and `supportedToolchains.ini` from it. Those give
   the Arm and RISC-V toolchain keys, the picotool version, and the CMake and
   ninja versions for the SDK you asked for. The files come from the repository
   rather than the published site, since that is where the version number came
   from and the site can briefly lag behind it after a release.
2. **Which release publishes each tool.** The script lists the releases of
   [`raspberrypi/pico-sdk-tools`](https://github.com/raspberrypi/pico-sdk-tools)
   and takes each asset from the newest release that publishes it - so
   `pico-sdk-tools-2.3.0-aarch64-lin.tar.gz` comes from whichever release built
   it most recently. OpenOCD's version is not in `versionBundles.json` at
   all, so it is read off the asset name.

The script stops with an explanatory error if either API call fails.
Unauthenticated requests are limited to 60 an hour *per IP*, so set
`GITHUB_TOKEN` (or `GH_TOKEN`, or pass `--github-token`) if you are hitting that
limit from your IP. The composite action passes the job's token automatically.

To override any of it: `--extension-data-url` pins the metadata to a particular
published data version, `--bundles` and `--toolchains-ini` read it from local
files instead, and `--pico-sdk-tools-tag`, `--picotool-tag` and `--openocd-tag`
pin an individual tool to a named pico-sdk-tools release.

## The `picorc` file

`~/.pico-sdk/picorc` is generated by the installer and rewritten on every run,
so don't edit it. It sits with the tools it describes, so deleting the install
directory takes it with it, and `--install-dir` moves both together. It prepends
each tool directory to `PATH` (skipping any that are already there, so sourcing
it twice is harmless) and exports:

| Variable                    | Purpose                                          |
| --------------------------- | ------------------------------------------------ |
| `PICO_ARM_TOOLCHAIN_PATH`   | Arm toolchain root, for `pico-examples`' universal targets |
| `PICO_RISCV_TOOLCHAIN_PATH` | RISC-V toolchain root, likewise                   |
| `picotool_DIR`              | So `find_package(picotool)` resolves without a build |
| `pioasm_DIR`                | So `find_package(pioasm)` resolves without a build |
| `OPENOCD_SCRIPTS`           | OpenOCD's script search path                      |
| `CMAKE_GENERATOR`           | `Ninja`, since CMake otherwise defaults to Unix Makefiles on Linux. Only when ninja is installed, and a `-G` on the command line still overrides this |
| `PICO_SDK_PATH`             | Whenever `~/.pico-sdk/sdk/<version>` exists       |

Note that `PICO_TOOLCHAIN_PATH` is **not** set. The SDK would search that one
directory first and *only* that directory, so pinning it to the Arm toolchain
makes every RISC-V configure print

```
CMake Warning: PICO_TOOLCHAIN_PATH specified (.../toolchain/15_2_Rel1),
but not found there
```

before falling back to `PATH` and finding the right compiler anyway. Both
toolchain `bin` directories are on `PATH`, and the SDK looks for a specific
triple (`arm-none-eabi-gcc`, or whichever `riscv32-*-gcc` the SDK version
pins), so leaving `PICO_TOOLCHAIN_PATH` unset lets it pick the correct one for
whichever `PICO_PLATFORM` you asked for, with no warning and nothing to change
between Arm and RISC-V builds.

The installer then adds a marked block to your shell rc file that sources it:

```sh
# >>> pico-sdk-tools installer >>>
# Added by install_pico_tools.py
if [ -f "${HOME}/.pico-sdk/picorc" ]; then . "${HOME}/.pico-sdk/picorc"; fi
# <<< pico-sdk-tools installer <<<
```

Prepending is deliberate. A distro `arm-none-eabi-gcc` is usually a different
release from the one the SDK version pins, and appending would let it win: on
Raspberry Pi OS, `gcc-arm-none-eabi` is 14.2 where SDK 2.3.0 wants 15.2. The
same goes for CMake and ninja, so the versions here shadow the system ones. If
you would rather keep your own, `--no-cmake` and `--no-ninja` leave them out.
The action gets the same result: the runner prepends whatever it reads from
`$GITHUB_PATH`, so those directories also come before the system ones.

The block is replaced rather than duplicated on re-runs. The rc file defaults to
`~/.zshrc` for `darwin_*` platforms and `~/.bashrc` otherwise; override it with
`--rc-file`, or use `--no-rc-include` to write `picorc` without touching any
shell config file, or `--no-picorc` to skip generating `picorc` altogether.

### On Windows

`picorc` is a POSIX shell script, so it only helps the Git Bash and MSYS2 side
of Windows. For `--platform win32_x64` a `picorc.ps1` is written next to it,
doing the same job for PowerShell, and included from
`$PROFILE.CurrentUserAllHosts`:

```powershell
if (Test-Path -LiteralPath "$HOME/.pico-sdk/picorc.ps1") { . "$HOME/.pico-sdk/picorc.ps1" }
```

The profile path is asked of PowerShell itself rather than assembled, so a
`Documents` folder redirected into OneDrive is handled, and PowerShell 7 and 5.1
each get their own. Override it with `--ps-profile`. If no `pwsh` or
`powershell` is on `PATH` the file is still written and the line to add is
printed instead.

## Use from GitHub Actions

This directory is also a composite action, so a workflow can install the tools
as a single step and have them on `PATH` for everything that follows.

### Setting it up

`action.yml` lives in this directory rather than at the repository root, so
callers name the directory too:

```yaml
uses: raspberrypi/pico-sdk-tools/installer@<ref>
```

`<ref>` is a branch name, tag, or full commit SHA - `@main` follows the tip of
main, a tag such as `@v2.3.0-1` follows a release, and a SHA pins the action.

The runner needs Python 3.9 or newer, which every GitHub-hosted runner already
has. There are no other dependencies.

### Using it

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: raspberrypi/pico-sdk-tools/installer@main
    with:
      sdk-version: '2.3.0'
      skip: riscv-toolchain,openocd   # optional

  - run: |
      cmake -S . -B build -G Ninja
      cmake --build build
```

Because the action runs as a step in your job, every later step sees the tools:
the compilers, `picotool`, `pioasm`, `cmake` and `ninja` are on `PATH`, and
`picotool_DIR`, `pioasm_DIR`, `PICO_ARM_TOOLCHAIN_PATH`,
`PICO_RISCV_TOOLCHAIN_PATH` and `OPENOCD_SCRIPTS` are in the environment. It
exports them through `$GITHUB_PATH` and `$GITHUB_ENV` and writes no `picorc`
at all, since Actions shells never read a shell rc file - which also means it
leaves no trace in the home directory of a self-hosted runner.

### Inputs

| Input                | Default                 | Notes                                              |
| -------------------- | ----------------------- | -------------------------------------------------- |
| `sdk-version`        | *(required)*            | e.g. `2.3.0`                                        |
| `platform`           | from `runner.os`/`arch` | Override to cross-download                          |
| `install-dir`        | `~/.pico-sdk`           |                                                     |
| `skip`               | *(none)*                | Space- or comma-separated component names           |
| `sdk`                | `false`                 | Clone the SDK too - see below                       |
| `openocd`            | `false`                 | Install OpenOCD too - see below                     |
| `cache`              | `true`                  | `actions/cache` over the install directory          |
| `extension-data-url` | newest published        | Pin a different Pico VS Code data version           |
| `github-token`       | `${{ github.token }}`   | Used for the API calls that resolve tool releases   |
| `extra-args`         | *(none)*                | Passed through to `install_pico_tools.py`           |

Outputs: `install-dir`, `platform`, `cache-hit`.

### The SDK

Cloning the SDK is off by default in the action. A workflow almost always checks
out its own SDK at a pinned ref, and the clone is a few hundred megabytes, which
would also bloat the cache. Turn it on when you want the action to provide it:

```yaml
  - uses: raspberrypi/pico-sdk-tools/installer@main
    with:
      sdk-version: '2.3.0'
      sdk: true
```

`PICO_SDK_PATH` is exported whenever an SDK is present in the install
directory, whether this run cloned it or a previous one did. The clone is
shallow, but still adds roughly 410 MB to the cache entry.

### OpenOCD

OpenOCD is the one component the action leaves out by default. A hosted runner
has no debug hardware attached, and the runner images do not carry the
`libftdi1` and `libhidapi-hidraw` libraries it links against, so installing it
costs a download and buys nothing. On a self-hosted runner with hardware:

```yaml
  - uses: raspberrypi/pico-sdk-tools/installer@main
    with:
      sdk-version: '2.3.0'
      openocd: true
```

It is a separate input rather than a default for `skip` so that naming other
components does not quietly bring OpenOCD back. `skip: openocd` still works, and
wins if you pass both.

### Caching

The action wraps the install directory in `actions/cache` by default. The key is
the platform, the SDK version and the newest `pico-sdk-tools` release tag, plus
a digest of the installer script and the remaining inputs. A warm cache turns
the install step into a restore, so there is no reason to add an
`actions/cache` block of your own. Set `cache: false` to opt out.

Two details the key has to respect: the release tag is in it so that a new
`pico-sdk-tools` release is picked up rather than masked by a stale cache, and
the rest is digested rather than interpolated because `actions/cache` rejects
any key containing a comma - which `skip` uses as its separator.

### Building for several platforms

`platform` defaults from `runner.os`/`runner.arch`, so an ordinary matrix needs
nothing extra:

```yaml
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        runs-on: [ubuntu-latest, ubuntu-24.04-arm, macos-latest, windows-latest]
    runs-on: ${{ matrix.runs-on }}
    steps:
      - uses: actions/checkout@v4
      - uses: raspberrypi/pico-sdk-tools/installer@main
        with:
          sdk-version: '2.3.0'
      - run: ./build.sh
```

### Worked example: pico-sdk-prebuilts

`raspberrypi/pico-sdk-prebuilts` builds the universal UF2s from
`pico-examples`, and uses this installer in one step:

```yaml
      - name: Install Toolchains & Tools
        uses: raspberrypi/pico-sdk-tools/installer@main
        with:
          sdk-version: ${{ env.SDK_TOOLS_VERSION }}

      - name: Checkout Pico SDK
        uses: actions/checkout@v6
        with:
          repository: ${{ env.PICO_SDK_REPO }}
          ref: ${{ env.PICO_SDK_TAG }}
          path: pico-sdk
          submodules: 'recursive'

      - name: Build Universal UF2s
        run: |
          cmake -S pico-examples -B build-universal -G "Ninja" \
            -D PICO_SDK_PATH="${{ github.workspace }}/pico-sdk" \
            -D PICO_ARM_TOOLCHAIN_PATH="$PICO_ARM_TOOLCHAIN_PATH" \
            -D PICO_RISCV_TOOLCHAIN_PATH="$PICO_RISCV_TOOLCHAIN_PATH"
          cmake --build build-universal --target hello_universal blink_universal nuke_universal
```

`picotool_DIR` and `pioasm_DIR` come from the environment the action set up,
and the compilers are found on `PATH`, so CMake needs no `-D` flags for either.
The universal examples are the exception: they check that
`PICO_ARM_TOOLCHAIN_PATH` and `PICO_RISCV_TOOLCHAIN_PATH` are *defined as CMake
variables*, and use them to point each per-architecture sub-build at the right
toolchain, so those two are passed explicitly, reading the values back out of
the environment.

## All options

```
usage: install_pico_tools.py [-h] [--platform {linux_x64,linux_arm64,darwin_x64,darwin_arm64,win32_x64}]
                             [--install-dir INSTALL_DIR]
                             [--no-sdk] [--no-arm-toolchain] [--no-riscv-toolchain]
                             [--no-pico-sdk-tools] [--no-picotool] [--no-openocd]
                             [--no-cmake] [--no-ninja]
                             [--picorc PICORC] [--no-picorc]
                             [--rc-file RC_FILE] [--no-rc-include]
                             [--github-path]
                             [--extension-data-url URL] [--github-token TOKEN]
                             [--bundles BUNDLES] [--toolchains-ini TOOLCHAINS_INI]
                             [--pico-sdk-tools-tag TAG] [--picotool-tag TAG]
                             [--openocd-tag TAG] [--openocd-version VERSION]
                             [--force] [--dry-run]
                             sdk_version
```

Notable extras:

- `--github-path` - also write the `PATH` entries and variables to the
  `$GITHUB_PATH` / `$GITHUB_ENV` files. This is how the composite action exports
  them, since GitHub Actions shells never read `.bashrc`. The runner prepends
  what it reads from `$GITHUB_PATH`, so the effect matches `picorc`.
- `--dry-run` - print the URLs and the resulting environment, change nothing.
- `--ps-profile` - PowerShell profile to include `picorc.ps1` from, for
  `win32_x64`. Defaults to whatever PowerShell reports as
  `$PROFILE.CurrentUserAllHosts`.
- `--github-token` - token for the two API calls, if `GITHUB_TOKEN` and
  `GH_TOKEN` are not set.
- `--bundles` / `--toolchains-ini` - use local copies of the extension data
  instead of fetching them. Passing both skips the data-version lookup entirely.
- `--pico-sdk-tools-tag` / `--picotool-tag` / `--openocd-tag` - take one tool
  from a named `pico-sdk-tools` release instead of the newest one publishing it.
- `--openocd-version` - install a specific OpenOCD version rather than whichever
  the newest release ships.

## Requirements

**Python 3.9 or newer**, standard library only - no `pip install` or
virtualenv needed.

`git` is needed only for cloning the SDK; without it that step is skipped with a
warning and everything else still installs.

The action installs no system packages. The one thing that needs them is
OpenOCD, which on Linux links against `libftdi1` and `libhidapi-hidraw` at
runtime - `sudo apt install libftdi1-2 libhidapi-hidraw0` if you intend to run
it.
