#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)

sdkVersion=$1

export PICO_SDK_PATH="$PWD/pico-sdk"
export LDFLAGS="-static -static-libgcc -static-libstdc++"

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
