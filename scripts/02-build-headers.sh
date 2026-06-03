#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 2: MinGW-w64 Headers ${MINGW_W64_VERSION}"
echo "========================================="

download_and_extract "${MINGW_W64_URL}" "${SRC_DIR}/mingw-w64"

mkdir -p "${BUILD_DIR}/headers"
cd "${BUILD_DIR}/headers"

"${SRC_DIR}/mingw-w64/mingw-w64-headers/configure" \
    --host="${TARGET}" \
    --prefix="${MINGW_PREFIX}" \
    --enable-sdk=all \
    --enable-idl \
    --without-widl \
    --with-default-win32-winnt=0xA00 \
    --with-default-msvcrt=ucrt

make install

# GCC expects the sysroot at /usr/<target>
ln -sfn "${MINGW_PREFIX}" "/usr/${TARGET}"

echo "==> MinGW-w64 headers installed to ${MINGW_PREFIX}/include/"
