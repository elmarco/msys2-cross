#!/bin/bash
set -euo pipefail

# Smoke test: build mingw-w64-zlib using makepkg-mingw
# Run inside the msys2-cross container.

echo "=== Test: Build mingw-w64-zlib ==="

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

cd "${WORKDIR}"

# Clone just the zlib package
git clone --filter=blob:none --sparse \
    https://github.com/msys2/MINGW-packages.git \
    MINGW-packages

cd MINGW-packages
git sparse-checkout add mingw-w64-zlib
cd mingw-w64-zlib

# Build it
makepkg-mingw \
    --skipchecksums \
    --skippgpcheck \
    --nocheck \
    --force

# Verify the package was created
pkg_count=$(ls -1 *.pkg.tar.zst 2>/dev/null | wc -l)
if [[ "${pkg_count}" -eq 0 ]]; then
    echo "FAIL: No package files produced"
    exit 1
fi

echo "PASS: Built ${pkg_count} package(s):"
ls -la *.pkg.tar.zst

# Verify we can install it
pacman --config /opt/msys2-cross/config/pacman-mingw.conf \
    -U --noconfirm *.pkg.tar.zst

# Verify files were installed
if [[ ! -f /ucrt64/lib/libz.a ]]; then
    echo "FAIL: libz.a not found in sysroot"
    exit 1
fi

echo "PASS: zlib installed successfully to /ucrt64/"
