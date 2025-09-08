#!/bin/bash

set -euo pipefail

# Defaults
SKIP_RISCV=${SKIP_RISCV-0}
SKIP_OPENOCD=${SKIP_OPENOCD-0}

# Install prerequisites
sudo apt install -y jq cmake libtool automake libusb-1.0-0-dev libhidapi-dev libftdi1-dev libjim-dev patchelf
# RISC-V prerequisites
sudo apt install -y autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev ninja-build git cmake libglib2.0-dev libslirp-dev
# RPi Only prerequisites
if [[ $(uname -m) == 'aarch64' ]]; then
    sudo apt install -y libgpiod-dev
fi

repos=$(cat config/repositories.json | jq -c '.repositories[]')
export version=$(cat ./version.txt)
suffix="$(uname -m)-lin"
builddir="build"

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
    if ! ../packages/linux/openocd/build-openocd.sh; then
        echo "::error title=openocd-fail-${suffix}::OpenOCD Build Failed on Linux $(uname -m)"
        SKIP_OPENOCD=1
    fi
fi
if [[ "$SKIP_RISCV" != 1 ]]; then
    # Takes ages to build
    ../packages/linux/riscv/build-riscv-gcc.sh
fi
../packages/linux/picotool/build-picotool.sh
cd ..

topd=$PWD

if [ ${version:0:1} -ge 2 ]; then
    # Package pico-sdk-tools separately as well

    filename="pico-sdk-tools-${version}-${suffix}.tar.gz"

    echo "Saving pico-sdk-tools package to $filename"
    pushd "$builddir/pico-sdk-tools/"
    tar -a -cf "$topd/bin/$filename" * .keep
    popd
fi

# Package picotool separately as well
version=$("./$builddir/picotool-install/picotool/picotool" version -s)
echo "Picotool version $version"

filename="picotool-${version}-${suffix}.tar.gz"

echo "Saving picotool package to $filename"
pushd "$builddir/picotool-install/"
tar -a -cf "$topd/bin/$filename" * .keep
popd

if [[ "$SKIP_OPENOCD" != 1 ]]; then
    # Package OpenOCD separately as well

    version=($("./$builddir/openocd-install/usr/local/bin/openocd" --version 2>&1))
    version=${version[0]}
    version=${version[3]}
    version=$(echo $version | cut -d "-" -f 1)

    echo "OpenOCD version $version"

    filename="openocd-${version}-${suffix}.tar.gz"

    echo "Saving OpenOCD package to $filename"
    pushd "$builddir/openocd-install/usr/local/bin"
    tar -a -cf "$topd/bin/$filename" * -C "../share/openocd" "scripts"
    popd
fi

if [[ "$SKIP_RISCV" != 1 ]]; then
    # Package riscv toolchain separately as well
    version=$("./$builddir/riscv-install/bin/riscv32-unknown-elf-gcc" -dumpversion)
    version=$(echo $version | cut -d "." -f 1)
    echo "RISC-V Toolchain version $version"

    filename="riscv-toolchain-${version}-${suffix}.tar.gz"

    echo "Saving RISC-V Toolchain package to $filename"
    pushd "$builddir/riscv-install/"
    tar -a -cf "$topd/bin/$filename" *
    popd
fi
