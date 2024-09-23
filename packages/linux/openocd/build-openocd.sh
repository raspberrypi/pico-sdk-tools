#!/bin/bash

set -euo pipefail

cd openocd
sed -i -e 's/uint /unsigned int /g' ./src/flash/nor/rp2040.c
./bootstrap
./configure --disable-werror
make clean
make -j$(nproc)
INSTALLDIR="$PWD/../openocd-install/usr/local/bin"
rm -rf "$PWD/../openocd-install"
DESTDIR="$PWD/../openocd-install" make install
