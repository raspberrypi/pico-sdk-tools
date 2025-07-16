#!/bin/bash

set -euo pipefail

INSTALLDIR=$1
BINDIR=$2
BINNAME=$3

rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

cp -r $INSTALLDIR-arm64/* $INSTALLDIR
touch $INSTALLDIR/.keep

lipo -create -output $INSTALLDIR/$BINDIR/$BINNAME $INSTALLDIR-x86_64/$BINDIR/$BINNAME $INSTALLDIR-arm64/$BINDIR/$BINNAME

for f in $INSTALLDIR-arm64/$BINDIR/*.dylib; do
    if [ -f $INSTALLDIR-arm64/$BINDIR/$(basename $f) ]; then
        lipo -create -output $INSTALLDIR/$BINDIR/$(basename $f) $INSTALLDIR-x86_64/$BINDIR/$(basename $f) $INSTALLDIR-arm64/$BINDIR/$(basename $f)
    fi
done
