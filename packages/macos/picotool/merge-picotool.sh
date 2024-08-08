#!/bin/bash

INSTALLDIR="pico-sdk-tools"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

cp -r $INSTALLDIR-arm64/* $INSTALLDIR
touch $INSTALLDIR/.keep

lipo -create -output $INSTALLDIR/pioasm/pioasm $INSTALLDIR-x86_64/pioasm/pioasm $INSTALLDIR-arm64/pioasm/pioasm


INSTALLDIR="picotool-install"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

cp -r $INSTALLDIR-arm64/* $INSTALLDIR
touch $INSTALLDIR/.keep

lipo -create -output $INSTALLDIR/picotool/picotool $INSTALLDIR-x86_64/picotool/picotool $INSTALLDIR-arm64/picotool/picotool
lipo -create -output $INSTALLDIR/picotool/libusb-1.0.dylib $INSTALLDIR-x86_64/picotool/libusb-1.0.dylib $INSTALLDIR-arm64/picotool/libusb-1.0.dylib
