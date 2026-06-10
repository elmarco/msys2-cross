#!/bin/bash
set -euo pipefail

# Smoke test: build mingw-w64-zlib using makepkg-mingw.
# Expects MINGW-packages bind-mounted at /src (the standard layout).
# Run inside the msys2-cross container:
#   podman run --rm -v ./MINGW-packages:/src msys2-cross bash /opt/msys2-cross/tests/test-zlib.sh

echo "=== Test: Build mingw-w64-zlib ==="

PKG=mingw-w64-zlib
SRC_DIR="/src/${PKG}"

if [[ ! -d "${SRC_DIR}" ]]; then
    echo "FAIL: ${SRC_DIR} not found — bind-mount MINGW-packages at /src"
    exit 1
fi

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

cp -a "${SRC_DIR}" "${WORKDIR}/${PKG}"
cd "${WORKDIR}/${PKG}"

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
