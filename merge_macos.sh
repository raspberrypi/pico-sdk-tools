#!/bin/bash

set -euo pipefail

# Defaults
SKIP_RISCV=${SKIP_RISCV-0}
SKIP_OPENOCD=${SKIP_OPENOCD-0}
SKIP_PICOTOOL=${SKIP_PICOTOOL-0}

echo "Running on $(uname -m)"

export version=$(cat ./version.txt)
suffix="mac"
builddir="build"

cd $builddir
if [[ "$SKIP_OPENOCD" != 1 ]]; then
    ../packages/macos/make-universal.sh "openocd-install"
    echo "OpenOCD Merge Complete"
fi
if [[ "$SKIP_RISCV" != 1 ]]; then
    ../packages/macos/make-universal.sh "riscv-install"
    echo "RISC-V Merge Complete"
fi
if [[ "$SKIP_PICOTOOL" != 1 ]]; then
    ../packages/macos/make-universal.sh "picotool-install"
    echo "Picotool Merge Complete"

    if [ ${version:0:1} -ge 2 ]; then
        ../packages/macos/make-universal.sh "pico-sdk-tools"
        echo "Pico SDK Tools Merge Complete"
    fi
fi
cd ..

topd=$PWD

if [[ "$SKIP_PICOTOOL" != 1 ]]; then
    echo "Packaging picotool"
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
fi

if [[ "$SKIP_OPENOCD" != 1 ]]; then
    echo "Packaging OpenOCD"
    # Package OpenOCD separately as well

    version=($("./$builddir/openocd-install/openocd/openocd" --version 2>&1))
    version=${version[0]}
    version=${version[3]}
    version=$(echo $version | cut -d "-" -f 1)

    echo "OpenOCD version $version"

    filename="openocd-${version}-${suffix}.zip"

    echo "Saving OpenOCD package to $filename"
    pushd "$builddir/openocd-install/openocd"
    tar -a -cf "$topd/bin/$filename" *
    popd
fi

if [[ "$SKIP_RISCV" != 1 ]]; then
    echo "Packaging RISC-V Toolchain"
    # Package riscv toolchain separately as well
    version=$("./$builddir/riscv-install/bin/riscv32-unknown-elf-gcc" -dumpversion)
    version=$(echo $version | cut -d "." -f 1)
    echo "Risc-V Toolchain version $version"

    filename="riscv-toolchain-${version}-${suffix}.zip"

    echo "Saving RISC-V Toolchain package to $filename"
    pushd "$builddir/riscv-install/"
    tar -a -cf "$topd/bin/$filename" *
    popd
fi
