#!/bin/bash

set -euo pipefail

URL=$1
SUFFIX=$2

BASEINSTALLDIR="riscv-install"
INSTALLDIR="$BASEINSTALLDIR-$SUFFIX"
rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

BUILDDIR=$(pwd)

ZIPFILE=$(basename -- "$URL")
FILENAME="${ZIPFILE%.*}"

wget $URL
unzip $ZIPFILE -d $INSTALLDIR
mv $INSTALLDIR/$FILENAME/* $INSTALLDIR
rm -rf $INSTALLDIR/$FILENAME

# Remove existing multilibs
rm -rf $INSTALLDIR/lib/gcc/riscv32-unknown-elf/*/rv32*
rm -rf $INSTALLDIR/lib/gcc/riscv32-unknown-elf/*/rv64*
rm -rf $INSTALLDIR/riscv32-unknown-elf/lib/rv32*
rm -rf $INSTALLDIR/riscv32-unknown-elf/lib/rv64*

# Add new lib
cp -r $BASEINSTALLDIR/lib/gcc/riscv32-unknown-elf/*/rv32* $INSTALLDIR/lib/gcc/riscv32-unknown-elf/*/
cp -r $BASEINSTALLDIR/riscv32-unknown-elf/lib/rv32* $INSTALLDIR/riscv32-unknown-elf/lib/
