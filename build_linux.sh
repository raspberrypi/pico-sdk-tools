#!/bin/bash

set -euo pipefail

# Defaults
SKIP_RISCV=${SKIP_RISCV-0}
if git clone https://git.savannah.nongnu.org/git/git2cl.git; then
    SKIP_OPENOCD=${SKIP_OPENOCD-0}
else
    # Clone is failing, so skip build
    echo "Skipping openocd build, as likely to fail"
    SKIP_OPENOCD=${SKIP_OPENOCD-1}
fi

# Install prerequisites
sudo apt install -y jq cmake libtool automake libusb-1.0-0-dev libhidapi-dev libftdi1-dev
# Risc-V prerequisites
sudo apt install -y autoconf automake autotools-dev curl python3 python3-pip libmpc-dev libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev ninja-build git cmake libglib2.0-dev libslirp-dev

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
done < <(echo "$repos")


cd $builddir
if [[ "$SKIP_RISCV" != 1 ]]; then
    # Takes ages to build
    ../packages/linux/riscv/build-riscv-gcc.sh
fi
if [[ "$SKIP_OPENOCD" != 1 ]]; then
    ../packages/linux/openocd/build-openocd.sh
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
    version="14"
    echo "Risc-V Toolchain version $version"

    filename="riscv-toolchain-${version}-${suffix}.tar.gz"

    echo "Saving Risc-V Toolchain package to $filename"
    pushd "$builddir/riscv-install/"
    tar -a -cf "$topd/bin/$filename" *
    popd
fi
