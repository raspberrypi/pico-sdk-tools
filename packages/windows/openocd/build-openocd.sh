#!/bin/bash

set -euo pipefail

BITNESS=$1
ARCH=$2

cd openocd
sed -i -e 's/uint /unsigned int /g' ./src/flash/nor/rp2040.c
./bootstrap
./configure --disable-werror
make clean
make -j$(nproc)
DESTDIR="$PWD/../openocd-install" make install
cp "/mingw$BITNESS/bin/libhidapi-0.dll" "$PWD/../openocd-install/mingw$BITNESS/bin"
cp "/mingw$BITNESS/bin/libusb-1.0.dll" "$PWD/../openocd-install/mingw$BITNESS/bin"

# Removing files with special char in their names
# they cause issues with some decompression libraries
rm "$PWD/../openocd-install/mingw$BITNESS/scripts/target/1986*.cfg"
