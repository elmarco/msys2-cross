#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 4: MinGW-w64 CRT ${MINGW_W64_VERSION}"
echo "========================================="

# mingw-w64 source already downloaded in stage 2
if [[ ! -d "${SRC_DIR}/mingw-w64" ]]; then
    download_and_extract "${MINGW_W64_URL}" "${SRC_DIR}/mingw-w64"
fi

mkdir -p "${BUILD_DIR}/crt"
cd "${BUILD_DIR}/crt"

"${SRC_DIR}/mingw-w64/mingw-w64-crt/configure" \
    --host="${TARGET}" \
    --prefix="${MINGW_PREFIX}" \
    --with-default-msvcrt=ucrt \
    --enable-lib64 \
    --disable-lib32 \
    --enable-static \
    --enable-shared

make -j"${JOBS}"
make install

echo "==> MinGW-w64 CRT installed to ${MINGW_PREFIX}/lib/"
