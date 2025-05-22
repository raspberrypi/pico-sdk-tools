#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)

sdkVersion=$1

export PICO_SDK_PATH="$PWD/pico-sdk"
export LDFLAGS="-static -static-libgcc -static-libstdc++"

# Apply https://github.com/raspberrypi/pico-sdk/commit/66540fe88e86a9f324422b7451a3b5dff4c0449f for gcc 15
git -C "$PICO_SDK_PATH" fetch origin 66540fe88e86a9f324422b7451a3b5dff4c0449f
git -C "$PICO_SDK_PATH" cherry-pick -n 66540fe88e86a9f324422b7451a3b5dff4c0449f

git -C "$PICO_SDK_PATH" submodule update --init --depth=1 lib/mbedtls

echo "Version is $sdkVersion"
if [ ${sdkVersion:0:1} -ge 2 ]; then
    echo "Version 2+"
    cd pico-sdk/tools/pioasm
    mkdir -p build
    cd build
    cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -DPIOASM_FLAT_INSTALL=1 -Wno-dev
    cmake --build .

    cd ../../../..
    INSTALLDIR="pico-sdk-tools/${MSYSTEM,,}"
    mkdir -p $INSTALLDIR
    cmake --install pico-sdk/tools/pioasm/build/ --prefix $INSTALLDIR
    touch $INSTALLDIR/.keep
else
    echo "Version <2"

    echo "Cloning older SDK for tools"
    rm -rf "pico-sdk-$sdkVersion"
    git clone -b "$sdkVersion" --depth=1 -c advice.detachedHead=false "https://github.com/raspberrypi/pico-sdk.git" "pico-sdk-$sdkVersion"

    cd pico-sdk-$sdkVersion/tools/elf2uf2
    mkdir -p build
    cd build
    cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -Wno-dev
    cmake --build .

    cd ../../pioasm
    mkdir -p build
    cd build
    cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -Wno-dev
    cmake --build .

    cd ../../../..
    INSTALLDIR="pico-sdk-tools/${MSYSTEM,,}"
    mkdir -p $INSTALLDIR
    cp pico-sdk-$sdkVersion/tools/elf2uf2/build/elf2uf2.exe $INSTALLDIR
    cp pico-sdk-$sdkVersion/tools/pioasm/build/pioasm.exe $INSTALLDIR
    cp ../packages/windows/pico-sdk-tools/pico-sdk-tools-config.cmake $INSTALLDIR
fi

cd picotool

# Apply https://github.com/raspberrypi/picotool/commit/f010190c37061f9a207075c6918a5e6e9aee5653 for CMake 4.x
git fetch origin f010190c37061f9a207075c6918a5e6e9aee5653
git cherry-pick -n f010190c37061f9a207075c6918a5e6e9aee5653

# Apply https://github.com/raspberrypi/picotool/commit/ac8aaeac7e7c2dfb55a277c5aa4ff6537612789d for GCC 15
git fetch origin ac8aaeac7e7c2dfb55a277c5aa4ff6537612789d
git cherry-pick -n ac8aaeac7e7c2dfb55a277c5aa4ff6537612789d

mkdir -p build
cd build
cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -DPICOTOOL_FLAT_INSTALL=1
cmake --build .

cd ../..
INSTALLDIR="picotool-install/${MSYSTEM,,}"
mkdir -p $INSTALLDIR
cmake --install picotool/build/ --prefix $INSTALLDIR
touch $INSTALLDIR/.keep
cd $INSTALLDIR/picotool
"$BUILDDIR/../packages/windows/copy-deps.sh"
