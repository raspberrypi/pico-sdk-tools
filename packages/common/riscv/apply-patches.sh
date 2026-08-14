#!/bin/bash

set -euo pipefail

BUILDDIR=$(pwd)
PATCHESDIR=$BUILDDIR/../packages/common/riscv/patches

cd riscv-gnu-toolchain

for dir in "${PATCHESDIR}"/*/; do
    component="$(basename "${dir}")"

    echo "Checking out ${component}"
    git submodule update --init --progress --depth 1 ${component}

    # git am requires user name and email
    echo "Setting Git user for ${component}"
    git -C "${component}" config user.name 'github-actions[bot]'
    git -C "${component}" config user.email 'github-actions[bot]@users.noreply.github.com'

    for patch in "${dir}"*.patch; do
        [[ -e "${patch}" ]] || continue
        echo "Applying ${patch} to ${component}"
        git -C "${component}" am "${patch}"
    done
done
