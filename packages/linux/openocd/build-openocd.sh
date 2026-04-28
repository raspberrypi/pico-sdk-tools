#!/bin/bash

set -euo pipefail

export CFLAGS=-static
export LDFLAGS=-static

BUILDDIR=$(pwd)
INSTALLDIR="openocd-install"
BINDIR="/openocd"
DATADIR="/"

cd openocd
./bootstrap
./configure --disable-werror --enable-internal-jimtcl --bindir="$BINDIR" --datadir="$DATADIR"
make clean
make
rm -rf "$BUILDDIR/$INSTALLDIR"
DESTDIR="$BUILDDIR/$INSTALLDIR" make install

# Add libraries that may be different versions on the system
cd "$BUILDDIR/$INSTALLDIR/$BINDIR"
find . -maxdepth 1 ! -name . ! -name .. ! -name openocd ! -name scripts -exec rm -r {} +
if [[ $(uname -m) == 'aarch64' ]]; then
    cp $(ldd openocd | egrep -o "(/.*/libgpiod\.so\.\S*)") ./
fi
patchelf --set-rpath '$ORIGIN' openocd
