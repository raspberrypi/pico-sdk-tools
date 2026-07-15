#!/bin/bash

set -euo pipefail

# Defaults
SKIP_RISCV=${SKIP_RISCV-0}
SKIP_OPENOCD=${SKIP_OPENOCD-0}
SKIP_PICOTOOL=${SKIP_PICOTOOL-0}

echo "Running on $(uname -m)"

# Install prerequisites
if [[ $(uname -m) == 'arm64' ]]; then
    arch -arm64 /opt/homebrew/bin/brew  install jq libtool libusb automake hidapi --quiet
else
    arch -x86_64 /usr/local/bin/brew    install jq libtool libusb automake hidapi --quiet
fi
# RISC-V prerequisites
echo "Listing local"
ls /usr/local/bin
rm /usr/local/bin/2to3* || true
rm /usr/local/bin/idle3* || true
rm /usr/local/bin/pip* || true
rm /usr/local/bin/py* || true
if [[ $(uname -m) == 'arm64' ]]; then
    arch -arm64 /opt/homebrew/bin/brew  install python3 gawk gnu-sed make gmp mpfr libmpc isl zlib expat texinfo flock libslirp --quiet
else
    arch -x86_64 /usr/local/bin/brew    install python3 gawk gnu-sed make gmp mpfr libmpc isl zlib expat texinfo flock libslirp --quiet
fi

repos=$(cat config/repositories.json | jq -c '.repositories.[]')
export version=$(cat ./version.txt)
suffix="mac"
builddir="build"

# nproc alias
alias nproc="sysctl -n hw.logicalcpu"

mkdir -p $builddir
mkdir -p "bin"

while read -r repo
do
    tree=$(echo "$repo" | jq -r .tree)
    href=$(echo "$repo" | jq -r .href)
    filename=$(basename -- "$href")
    extension="${filename##*.}"
    filename="${filename%.*}"
    filename=${filename%"-rp2350"}
    repodir="$builddir/${filename}"

    echo "${href} ${tree} ${filename} ${extension} ${repodir}"
    rm -rf "${repodir}"
    git clone -b "${tree}" --depth=1 -c advice.detachedHead=false "${href}" "${repodir}"
    submodules=$(echo "$repo" | jq -r .submodules)
    if [[ "$submodules" == "true" ]]; then
        git -C "${repodir}" submodule update --init --depth=1
    fi
done < <(echo "$repos")


cd $builddir
if [[ "$SKIP_OPENOCD" != 1 ]]; then
    if ! ../packages/macos/openocd/build-openocd.sh; then
        echo "::error title=openocd-fail-macos::OpenOCD Build Failed on macOS"
        SKIP_OPENOCD=1
    fi
    echo "OpenOCD Build Complete"
    if [[ "$SKIP_OPENOCD" != 1 ]]; then
        ../packages/macos/get-dylibs.sh "openocd-install-$(uname -m)"
        echo "OpenOCD dylibs copied"
    fi
fi
if [[ "$SKIP_RISCV" != 1 ]]; then
    # Takes ages to build
    ../packages/common/riscv/apply-patches.sh
    ../packages/macos/riscv/build-riscv-gcc.sh
    echo "RISC-V Build Complete"

    ../packages/macos/get-dylibs.sh "riscv-install-$(uname -m)"
    echo "RISC-V dylibs copied"
fi
if [[ "$SKIP_PICOTOOL" != 1 ]]; then
    ../packages/macos/picotool/build-picotool.sh
    echo "Picotool Build Complete"

    ../packages/macos/get-dylibs.sh "picotool-install-$(uname -m)"
    echo "Picotool dylibs copied"
fi
cd ..
