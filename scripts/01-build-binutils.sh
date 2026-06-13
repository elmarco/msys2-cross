#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 1: Cross-Binutils ${BINUTILS_VERSION}"
echo "========================================="

download_and_extract "${BINUTILS_URL}" "${SRC_DIR}/binutils-${BINUTILS_VERSION}"

mkdir -p "${BUILD_DIR}/binutils"
cd "${BUILD_DIR}/binutils"

"${SRC_DIR}/binutils-${BINUTILS_VERSION}/configure" \
    --target="${TARGET}" \
    --prefix=/usr \
    --with-sysroot="/usr/${TARGET}" \
    --disable-multilib \
    --disable-nls \
    --disable-shared \
    --disable-werror \
    --enable-deterministic-archives \
    --enable-lto \
    --enable-plugins \
    --enable-64-bit-bfd \
    --with-system-zlib

make -j"${JOBS}"
make install DESTDIR="${DESTDIR}"

echo "==> Cross-binutils installed to ${DESTDIR}/usr/bin/${TARGET}-*"
