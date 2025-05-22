#!/bin/bash

set -euo pipefail

# Defaults
SKIP_RISCV=${SKIP_RISCV-0}
SKIP_OPENOCD=${SKIP_OPENOCD-0}

# Install prerequisites
arch -x86_64 /usr/local/bin/brew install jq libtool libusb automake hidapi jimtcl --quiet
arch -arm64 /opt/homebrew/bin/brew install jq libtool libusb automake hidapi jimtcl --quiet
# RISC-V prerequisites
echo "Listing local"
ls /usr/local/bin
rm /usr/local/bin/2to3* || true
rm /usr/local/bin/idle3* || true
rm /usr/local/bin/pip* || true
rm /usr/local/bin/py* || true
arch -x86_64 /usr/local/bin/brew install python3 gawk gnu-sed make gmp mpfr libmpc isl zlib expat texinfo flock libslirp --quiet
arch -arm64 /opt/homebrew/bin/brew install python3 gawk gnu-sed make gmp mpfr libmpc isl zlib expat texinfo flock libslirp --quiet

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
if [[ "$SKIP_OPENOCD" != 1 ]] && [[ $(uname -m) == 'arm64' ]]; then
    if ! ../packages/macos/openocd/build-openocd.sh; then
        echo "::error title=openocd-fail-macos::OpenOCD Build Failed on macOS"
        SKIP_OPENOCD=1
    fi
fi
if [[ "$SKIP_RISCV" != 1 ]]; then
    # Takes ages to build
    ../packages/macos/riscv/build-riscv-gcc.sh
fi
arch -x86_64 ../packages/macos/picotool/build-picotool.sh
arch -arm64 ../packages/macos/picotool/build-picotool.sh
../packages/macos/picotool/merge-picotool.sh
cd ..

topd=$PWD
if [ ${version:0:1} -ge 2 ]; then
    # Package pico-sdk-tools separately as well

    filename="pico-sdk-tools-${version}-${suffix}.zip"

    echo "Saving pico-sdk-tools package to $filename"
    pushd "$builddir/pico-sdk-tools/"
    tar -a -cf "$topd/bin/$filename" * .keep
    popd
fi

# Package picotool separately as well
version=$("./$builddir/picotool-install/picotool/picotool" version -s)
echo "Picotool version $version"

filename="picotool-${version}-${suffix}.zip"

echo "Saving picotool package to $filename"
pushd "$builddir/picotool-install/"
tar -a -cf "$topd/bin/$filename" * .keep
popd

if [[ "$SKIP_OPENOCD" != 1 ]] && [[ $(uname -m) == 'arm64' ]]; then
    # Package OpenOCD separately as well

    version=($("./$builddir/openocd-install/usr/local/bin/openocd" --version 2>&1))
    version=${version[0]}
    version=${version[3]}
    version=$(echo $version | cut -d "-" -f 1)

    echo "OpenOCD version $version"

    filename="openocd-${version}-arm64-${suffix}.zip"

    echo "Saving OpenOCD package to $filename"
    pushd "$builddir/openocd-install/usr/local/bin"
    tar -a -cf "$topd/bin/$filename" * -C "../share/openocd" "scripts"
    popd
fi

if [[ "$SKIP_RISCV" != 1 ]]; then
    # Package riscv toolchain separately as well
    version="14"
    echo "Risc-V Toolchain version $version"

    filename="riscv-toolchain-${version}-arm64-${suffix}.zip"

    echo "Saving RISC-V Toolchain package to $filename"
    pushd "$builddir/riscv-install/"
    tar -a -cf "$topd/bin/$filename" *
    popd

    # Package x64-mac riscv toolchain separately as well
    version="14"
    echo "RISC-V Toolchain version $version"

    filename="riscv-toolchain-${version}-x64-mac.zip"

    echo "Saving RISC-V Toolchain package to $filename"
    pushd "$builddir/riscv-install-x64-mac/"
    tar -a -cf "$topd/bin/$filename" *
    popd
fi
