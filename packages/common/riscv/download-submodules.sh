#!/bin/bash

# Populate the sourceware.org-hosted submodules of riscv-gnu-toolchain from
# release tarballs on the UK Mirror Service, for use while sourceware.org is
# unreachable.  Run from the build directory, before apply-patches.sh, as the
# top level build scripts do.
#
# Each tarball below is the release that riscv-gnu-toolchain pins its submodule
# to, so the sources are those a working `git submodule update` would check out:
#
#     gdb-17.1            "Set GDB version number to 17.1."
#     newlib-4.6.0        "Changes for 4.6.0 snapshot"
#
# Those commits are listed below too, and are checked against the ones
# riscv-gnu-toolchain actually pins, so that updating the toolchain does not
# quietly leave this script fetching the sources for the previous one.

set -euo pipefail

MIRROR=https://www.mirrorservice.org/sites/sourceware.org/pub

BUILDDIR=$(pwd)
TARBALLDIR=$(mktemp -d)
trap 'rm -rf "${TARBALLDIR}"' EXIT

# component|path under $MIRROR|sha512 of the tarball|commit the tarball matches
SUBMODULES=(
    "gdb|gdb/releases/gdb-17.1.tar.xz|f1a6751e439a2128fecf3eae8b57c1608a0dc7cfe79b4356a937874e5a42bb2df0aba36eb6a9452c41966908b9a59076c7cad9720f684688ab956b65080f1d7c|631a49c452a4a456dd9889d172541ea789f8bcae"
    "newlib|newlib/newlib-4.6.0.20260123.tar.gz|ffa16d6465c0b429264c46395fa760fbcf072d3ff86e87330ba1f483efcfe66393ef83b03932759444a0ebeaef94d3ca58a59e91ab7b97b2a6ac6be2e7589657|8ba4275b83ec27529f67e0d477611fa6d8d6e6bd"
)

# macOS has shasum rather than sha512sum
verify_sha512() {
    local file="$1" expected="$2" actual

    if command -v sha512sum > /dev/null 2>&1; then
        actual=$(sha512sum "${file}" | cut -d ' ' -f 1)
    else
        actual=$(shasum -a 512 "${file}" | cut -d ' ' -f 1)
    fi

    if [[ "${actual}" != "${expected}" ]]; then
        echo "Checksum mismatch for ${file}" >&2
        echo "  expected ${expected}" >&2
        echo "  actual   ${actual}" >&2
        return 1
    fi
}

cd "${BUILDDIR}"/riscv-gnu-toolchain

for submodule in "${SUBMODULES[@]}"; do
    IFS='|' read -r component path sha512 commit <<< "${submodule}"

    if [[ -e "${component}/.git" ]]; then
        echo "Skipping ${component}, which is already checked out"
        continue
    fi

    pinned=$(git ls-tree HEAD -- "${component}" | awk '{print $3}')
    if [[ "${pinned}" != "${commit}" ]]; then
        echo "riscv-gnu-toolchain pins ${component} at ${pinned}," >&2
        echo "but $(basename "${path}") is ${commit}." >&2
        echo "Update SUBMODULES in $(basename "$0") to match, or check out" >&2
        echo "${component} with Git if sourceware.org is reachable again." >&2
        exit 1
    fi

    tarball="${TARBALLDIR}/$(basename "${path}")"

    echo "Downloading $(basename "${path}") for ${component}, pinned at ${commit}"
    curl --fail --location --retry 3 --output "${tarball}" "${MIRROR}/${path}"

    echo "Verifying $(basename "${tarball}")"
    verify_sha512 "${tarball}" "${sha512}"

    echo "Extracting $(basename "${tarball}") to ${component}"
    mkdir -p "${component}"
    tar -x -f "${tarball}" -C "${component}" --strip-components 1

    # apply-patches.sh applies the patches with git am, and the
    # riscv-gnu-toolchain Makefile takes <component>/.git as the marker that a
    # submodule has been checked out, so make the extracted tree a Git repo.
    echo "Creating a Git repository in ${component}"
    git -C "${component}" init -q
    git -C "${component}" add -A
    git -C "${component}" \
        -c user.name='github-actions[bot]' \
        -c user.email='github-actions[bot]@users.noreply.github.com' \
        commit -q -m "Import $(basename "${tarball}")"

    # Keep git submodule update from reaching for sourceware.org now that we
    # have populated this component by hand.
    git config "submodule.${component}.update" none
done
