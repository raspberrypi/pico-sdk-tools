#!/bin/bash

INSTALLDIR=$1

EXES=$(find $INSTALLDIR -type f -perm -u+x)
LIBS=$(otool -L $EXES | grep -E "/opt/homebrew|/usr/local/opt" | grep -v python | sort | uniq | grep -o -E "/.*\.dylib")

if [ ! $LIBS ]; then
    exit 1;
fi

while IFS= read -r lib; do
    echo
    echo $lib
    libname=$(echo $lib | grep -o -E "[^/]*\.dylib")
    echo $libname
    echo
    while IFS= read -r exe; do
        if file $exe | grep "Mach-O 64-bit executable" > /dev/null; then
            if otool -L $exe | grep -o $lib > /dev/null; then
                echo "$exe $(otool -L $exe | grep -o $lib)"
                exedir=$(echo $exe | grep -o -E ".*/")
                install_name_tool -change $lib @loader_path/$libname $exe
                if ! otool -l $exe | grep "LC_RPATH" -A2 | grep "@loader_path" > /dev/null; then
                    install_name_tool -add_rpath @loader_path/ $exe
                fi
                if [ ! -f $exedir$libname ]; then
                    cp $lib $exedir$libname
                fi
            fi
        fi
    done <<< "$EXES"
done <<< "$LIBS"
