#!/bin/bash

# Build pioasm (pico-sdk-tools) and picotool.  Run from the build directory,
# by build.sh.

set -euo pipefail

BUILDDIR=$(pwd)

export PICO_SDK_PATH="$BUILDDIR/pico-sdk"

if [[ $PLATFORM == windows ]]; then
    export LDFLAGS="-static -static-libgcc -static-libstdc++"
    export CMAKE_GENERATOR=Ninja
fi

# build_tool <source directory> [cmake arguments...]
build_tool() {
    local src=$1
    shift
    rm -rf "$src/build"
    cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release "$@"
    cmake --build "$src/build"
}

git -C "$PICO_SDK_PATH" submodule update --init --depth=1 lib/mbedtls

INSTALLDIR="pico-sdk-tools${ARCH_SUFFIX}"
if [[ ${version%%.*} -ge 2 ]]; then
    build_tool pico-sdk/tools/pioasm -DPIOASM_FLAT_INSTALL=1 -DPIOASM_VERSION_STRING="$version" -Wno-dev

    rm -rf "$INSTALLDIR"
    mkdir -p "$INSTALLDIR"
    cmake --install pico-sdk/tools/pioasm/build --prefix "$INSTALLDIR"
    touch "$INSTALLDIR/.keep"
elif [[ $PLATFORM == windows ]]; then
    echo "Cloning older SDK for tools"
    oldsdk="pico-sdk-$version"
    rm -rf "$oldsdk"
    git clone -b "$version" --depth=1 -c advice.detachedHead=false "https://github.com/raspberrypi/pico-sdk.git" "$oldsdk"

    build_tool "$oldsdk/tools/elf2uf2" -Wno-dev
    build_tool "$oldsdk/tools/pioasm" -Wno-dev

    rm -rf "$INSTALLDIR"
    mkdir -p "$INSTALLDIR"
    cp "$oldsdk/tools/elf2uf2/build/elf2uf2.exe" "$oldsdk/tools/pioasm/build/pioasm.exe" "$INSTALLDIR"
    cp ../packages/windows/pico-sdk-tools/pico-sdk-tools-config.cmake "$INSTALLDIR"
    sed "s/[$]sdkVersion/$version/" ../packages/windows/pico-sdk-tools/pico-sdk-tools-config-version.cmake \
        > "$INSTALLDIR/pico-sdk-tools-config-version.cmake"
fi

build_tool picotool -DPICOTOOL_FLAT_INSTALL=1

INSTALLDIR="picotool-install${ARCH_SUFFIX}"
rm -rf "$INSTALLDIR"
mkdir -p "$INSTALLDIR"
cmake --install picotool/build --prefix "$INSTALLDIR"
touch "$INSTALLDIR/.keep"

if [[ $PLATFORM == windows ]]; then
    cd "$INSTALLDIR/picotool"
    "$BUILDDIR/../packages/windows/copy-deps.sh"
fi
