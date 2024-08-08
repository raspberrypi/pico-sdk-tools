#!/bin/bash

set -euo pipefail

export PICO_SDK_PATH="$PWD/pico-sdk"

git -C "$PICO_SDK_PATH" submodule update --init --depth=1 lib/mbedtls

if [ ${version:0:1} -ge 2 ]; then
    cd pico-sdk/tools/pioasm
    rm -rf build
    mkdir -p build
    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DPIOASM_FLAT_INSTALL=1 -Wno-dev
    cmake --build .

    cd ../../../..
    INSTALLDIR="pico-sdk-tools-$(uname -m)"
    rm -rf $INSTALLDIR
    mkdir -p $INSTALLDIR
    cmake --install pico-sdk/tools/pioasm/build/ --prefix $INSTALLDIR
    touch $INSTALLDIR/.keep
fi

cd picotool
rm -rf build
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DPICOTOOL_FLAT_INSTALL=1
cmake --build .

cd ../..
INSTALLDIR="picotool-install-$(uname -m)"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR
cmake --install picotool/build/ --prefix $INSTALLDIR
touch $INSTALLDIR/.keep

libpath=($(otool -L $INSTALLDIR/picotool/picotool | grep libusb))
echo ${libpath[0]}
cp "${libpath[0]}" $INSTALLDIR/picotool/libusb-1.0.dylib
install_name_tool -change "${libpath[0]}" @loader_path/libusb-1.0.dylib $INSTALLDIR/picotool/picotool
install_name_tool -add_rpath @loader_path/ $INSTALLDIR/picotool/picotool
