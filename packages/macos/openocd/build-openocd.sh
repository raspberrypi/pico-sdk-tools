#!/bin/bash

set -euo pipefail

cd openocd

./bootstrap
# See https://github.com/raspberrypi/openocd/issues/30
# ./configure --disable-werror CAPSTONE_CFLAGS="$(pkg-config capstone --cflags | sed s/.capstone\$//)"
./configure --disable-werror
make clean
make
INSTALLDIR="$PWD/../openocd-install-$(uname -m)/usr/local/bin"
rm -rf "$PWD/../openocd-install-$(uname -m)"
DESTDIR="$PWD/../openocd-install-$(uname -m)" make install

libusbpath=($(otool -L $INSTALLDIR/openocd | grep libusb))
echo ${libusbpath[0]}
cp "${libusbpath[0]}" $INSTALLDIR/libusb-1.0.dylib
install_name_tool -change "${libusbpath[0]}" @loader_path/libusb-1.0.dylib $INSTALLDIR/openocd
libhidpath=($(otool -L $INSTALLDIR/openocd | grep libhidapi))
echo ${libhidpath[0]}
cp "${libhidpath[0]}" $INSTALLDIR/libhidapi.dylib
install_name_tool -change "${libhidpath[0]}" @loader_path/libhidapi.dylib $INSTALLDIR/openocd
libjimpath=($(otool -L $INSTALLDIR/openocd | grep libjim))
echo ${libjimpath[0]}
cp "${libjimpath[0]}" $INSTALLDIR/libjim0.83.dylib
install_name_tool -change "${libjimpath[0]}" @loader_path/libjim0.83.dylib $INSTALLDIR/openocd
install_name_tool -add_rpath @loader_path/ $INSTALLDIR/openocd
