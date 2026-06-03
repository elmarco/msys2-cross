#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 3: Bootstrap GCC ${GCC_VERSION} (C only)"
echo "========================================="

download_and_extract "${GCC_URL}" "${SRC_DIR}/gcc-${GCC_VERSION}"

mkdir -p "${BUILD_DIR}/gcc-bootstrap"
cd "${BUILD_DIR}/gcc-bootstrap"

"${SRC_DIR}/gcc-${GCC_VERSION}/configure" \
    --target="${TARGET}" \
    --prefix=/usr \
    --enable-languages=c \
    --disable-threads \
    --disable-shared \
    --disable-multilib \
    --disable-nls \
    --disable-werror \
    --disable-libssp \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libstdcxx \
    --with-arch=nocona \
    --with-tune=generic \
    --with-newlib

make -j"${JOBS}" all-gcc
make install-gcc

echo "==> Bootstrap GCC (C only) installed"
