#!/bin/bash

# Build OpenOCD.  Run from the build directory, by build.sh.

set -euo pipefail

BUILDDIR=$(pwd)
INSTALLDIR="openocd-install${ARCH_SUFFIX}"
BINDIR="/install/openocd"
DATADIR="/install"

if [[ $PLATFORM == linux ]]; then
    export CFLAGS=-static
    export LDFLAGS=-static
fi

cd openocd
./bootstrap
# See https://github.com/raspberrypi/openocd/issues/30
# ./configure --disable-werror CAPSTONE_CFLAGS="$(pkg-config capstone --cflags | sed s/.capstone\$//)"
./configure --disable-werror --enable-internal-jimtcl --bindir="$BINDIR" --datadir="$DATADIR"
make clean
make
rm -rf "$BUILDDIR/$INSTALLDIR"
DESTDIR="$BUILDDIR/$INSTALLDIR" make install

cd "$BUILDDIR/$INSTALLDIR/$BINDIR"
find . -maxdepth 1 ! -name . ! -name openocd ! -name openocd.exe ! -name scripts -exec rm -r {} +

case $PLATFORM in
    linux)
        # Add libraries that may be different versions on the system
        if [[ $(uname -m) == 'aarch64' ]]; then
            cp $(ldd openocd | grep -E -o "(/.*/libgpiod\.so\.\S*)") ./
        fi
        patchelf --set-rpath '$ORIGIN' openocd
        ;;
    windows)
        "$BUILDDIR/../packages/windows/copy-deps.sh"
        ;;
esac
