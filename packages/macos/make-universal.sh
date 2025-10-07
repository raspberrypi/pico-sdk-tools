#!/bin/bash

set -euo pipefail

INSTALLDIR=$1

rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

cp -r $INSTALLDIR-arm64/* $INSTALLDIR
touch $INSTALLDIR/.keep

FILES=$(find $INSTALLDIR -type f)
echo "Files: $FILES"
while IFS= read -r file; do
    file_arm64=$(sed "s|$INSTALLDIR|$INSTALLDIR-arm64|" <<< $file)
    file_x86_64=$(sed "s|$INSTALLDIR|$INSTALLDIR-x86_64|" <<< $file)
    if file $file | grep "Mach-O 64-bit executable" > /dev/null; then
        echo "Processing executable: $file $file_x86_64 $file_arm64"
        lipo -create -output $file $file_x86_64 $file_arm64
    elif file $file | grep "Mach-O 64-bit dynamic library" > /dev/null; then
        echo "Processing dynamic library: $file $file_x86_64 $file_arm64"
        lipo -create -output $file $file_x86_64 $file_arm64
    fi
done <<< "$FILES"
