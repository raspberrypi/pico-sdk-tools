#!/bin/zsh

set -euo pipefail

# Drop git repo of dtc as we use brew to build
rm -rf dtc
mkdir -p dtc-install
cd dtc-install

arch -x86_64 /usr/local/bin/brew install --build-from-source dtc
arch -arm64 /opt/homebrew/bin/brew install --build-from-source dtc

# Copy the dtc binaries to the build directory
BREW_PREFIX_X86=$(arch -x86_64 /usr/local/bin/brew --prefix)
BREW_PREFIX_ARM64=$(arch -arm64 /opt/homebrew/bin/brew --prefix)

cp -R "$BREW_PREFIX_X86/Cellar/dtc/$(arch -x86_64 /usr/local/bin/brew list --versions dtc | awk '{print $2}')" ./dtc-x86
cp -R "$BREW_PREFIX_ARM64/Cellar/dtc/$(arch -arm64 /opt/homebrew/bin/brew list --versions dtc | awk '{print $2}')" ./dtc-arm64

# Create universal distribution
mkdir -p dtc-universal/{bin,lib}

for binary in dtc fdtdump fdtoverlay fdtput fdtget dtdiff convert-dtsv0; do
  lipo -create \
    dtc-arm64/bin/$binary \
    dtc-x86/bin/$binary \
    -output dtc-universal/bin/$binary
done

VERSIONED_DYLIB=$(basename "$(find dtc-arm64/lib -name 'libfdt.dylib.*' | head -n 1)")

lipo -create \
  dtc-arm64/lib/$VERSIONED_DYLIB \
  dtc-x86/lib/$VERSIONED_DYLIB \
  -output dtc-universal/lib/$VERSIONED_DYLIB

lipo -create \
  dtc-arm64/lib/libfdt.a \
  dtc-x86/lib/libfdt.a \
  -output dtc-universal/lib/libfdt.a

# Recreate symlinks
cd dtc-universal/lib
ln -sf $VERSIONED_DYLIB libfdt.1.dylib
ln -sf libfdt.1.dylib libfdt.dylib
cd ../../

cp -R dtc-arm64/include dtc-universal/
cp -R dtc-arm64/README.md dtc-universal/

# clean up
rm -rf dtc-arm64
rm -rf dtc-x86

# move every folder and file from dtc-universal to .
mv dtc-universal/* .
rmdir dtc-universal

cd ..
