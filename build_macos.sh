#!/bin/bash

set -euo pipefail

# Install prerequisites
arch -x86_64 /usr/local/bin/brew install jq libtool libusb automake hidapi
arch -arm64 /opt/homebrew/bin/brew install jq libtool libusb automake hidapi

repos=$(cat config/repositories.json | jq -c '.repositories.[]')
export version=$(cat ./version.txt)
suffix="mac"
builddir="build"

mkdir -p $builddir
mkdir -p "bin"

while read -r repo
do
    tree=$(echo "$repo" | jq -r .tree)
    href=$(echo "$repo" | jq -r .href)
    filename=$(basename -- "$href")
    extension="${filename##*.}"
    filename="${filename%.*}"
    filename=${filename%"-rp2350"}
    repodir="$builddir/${filename}"

    pi_only=$(echo "$repo" | jq -r .pi_only)
    if [[ "$pi_only" == "true" ]]; then
        echo "Skipping Pi only $repodir"
        continue
    fi

    echo "${href} ${tree} ${filename} ${extension} ${repodir}"
    rm -rf "${repodir}"
    git clone -b "${tree}" --depth=1 -c advice.detachedHead=false "${href}" "${repodir}" 
done < <(echo "$repos")


cd $builddir
if [[ $(uname -m) == 'arm64' ]]; then
    ../packages/macos/openocd/build-openocd.sh
fi
arch -x86_64 ../packages/macos/picotool/build-picotool.sh
arch -arm64 ../packages/macos/picotool/build-picotool.sh
../packages/macos/picotool/merge-picotool.sh
cd ..

topd=$PWD
if [ ${version:0:1} -ge 2 ]; then
    # Package pico-sdk-tools separately as well

    filename="pico-sdk-tools-${version}-${suffix}.zip"

    echo "Saving pico-sdk-tools package to $filename"
    pushd "$builddir/pico-sdk-tools/"
    tar -a -cf "$topd/bin/$filename" * .keep
    popd
fi

# Package picotool separately as well
version=$("./$builddir/picotool-install/picotool/picotool" version -s)
echo "Picotool version $version"

filename="picotool-${version}-${suffix}.zip"

echo "Saving picotool package to $filename"
pushd "$builddir/picotool-install/"
tar -a -cf "$topd/bin/$filename" * .keep
popd

if [[ $(uname -m) == 'arm64' ]]; then
    # Package OpenOCD separately as well

    version=($("./$builddir/openocd-install/usr/local/bin/openocd" --version 2>&1))
    version=${version[0]}
    version=${version[3]}
    version=$(echo $version | cut -d "-" -f 1)

    echo "OpenOCD version $version"

    filename="openocd-${version}-arm64-${suffix}.zip"

    echo "Saving OpenOCD package to $filename"
    pushd "$builddir/openocd-install/usr/local/bin"
    tar -a -cf "$topd/bin/$filename" * -C "../share/openocd" "scripts"
    popd
fi
