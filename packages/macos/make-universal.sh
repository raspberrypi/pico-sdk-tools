#!/bin/bash

set -euo pipefail

INSTALLDIR=$1

rm -rf $INSTALLDIR
mkdir -p $INSTALLDIR

cp -r $INSTALLDIR-arm64/* $INSTALLDIR
touch $INSTALLDIR/.keep

EXES_arm=$(find $INSTALLDIR-arm64 -type f -perm -u+x)
LIBS_arm=$(find $INSTALLDIR-arm64 -type f -name "*.dylib")
FILES_arm=$(echo "$EXES_arm"$'\n'"$LIBS_arm" | sed "s|$INSTALLDIR-arm64|$INSTALLDIR|g")

EXES_x64=$(find $INSTALLDIR-x86_64 -type f -perm -u+x)
LIBS_x64=$(find $INSTALLDIR-x86_64 -type f -name "*.dylib")
FILES_x64=$(echo "$EXES_x64"$'\n'"$LIBS_x64" | sed "s|$INSTALLDIR-x86_64|$INSTALLDIR|g")

FILES=$(echo "$FILES_arm"$'\n'"$FILES_x64" | sort | uniq)

echo "Files: $FILES"
while IFS= read -r file; do
    file_arm64=$(sed "s|$INSTALLDIR|$INSTALLDIR-arm64|" <<< $file)
    file_x86_64=$(sed "s|$INSTALLDIR|$INSTALLDIR-x86_64|" <<< $file)
    if [ -f $file_x86_64 ]; then
        if [ -f $file_arm64 ]; then
            if file $file | grep "Mach-O 64-bit executable" > /dev/null; then
                echo "Processing executable: $file $file_x86_64 $file_arm64"
                lipo -create -output $file $file_x86_64 $file_arm64
            elif file $file | grep "Mach-O 64-bit dynamically linked shared library" > /dev/null; then
                echo "Processing dynamic library: $file $file_x86_64 $file_arm64"
                lipo -create -output $file $file_x86_64 $file_arm64
            fi
        else
            echo "Copying $file_x86_64 to $file"
            cp $file_x86_64 $file
        fi
    else
        echo "Leaving $file as is"
    fi
done <<< "$FILES"
