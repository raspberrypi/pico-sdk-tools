#!/bin/bash

set -euo pipefail

export CFLAGS=-static
export LDFLAGS=-static

cd openocd
./bootstrap
./configure --disable-werror
make clean
make
INSTALLDIR="$PWD/../openocd-install/usr/local/bin"
rm -rf "$PWD/../openocd-install"
DESTDIR="$PWD/../openocd-install" make install

# Add libraries that may be different versions on the system
cd $INSTALLDIR
if [[ $(uname -m) == 'aarch64' ]]; then
    cp $(ldd openocd | egrep -o "(/.*/libgpiod\.so\.\S*)") ./
fi
cp $(ldd openocd | egrep -o "(/.*/libjim\.so\.\S*)") ./
patchelf --set-rpath . openocd
