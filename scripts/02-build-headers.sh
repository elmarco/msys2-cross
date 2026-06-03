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

# GCC cross-compiler looks for headers in /usr/<target>/include and
# libraries in /usr/<target>/lib. Binutils (stage 1) already created
# /usr/<target>/ as a real directory, so we can't replace it with a
# symlink. Instead, symlink the include and lib subdirectories into it.
ln -sfn "${MINGW_PREFIX}/include" "/usr/${TARGET}/include"

# Move binutils' lib content (ldscripts) into the sysroot and replace
# with a symlink so GCC finds CRT libs in /usr/<target>/lib -> /ucrt64/lib
if [[ -d "/usr/${TARGET}/lib" && ! -L "/usr/${TARGET}/lib" ]]; then
    cp -a "/usr/${TARGET}/lib/"* "${MINGW_PREFIX}/lib/" 2>/dev/null || true
    rm -rf "/usr/${TARGET}/lib"
fi
ln -sfn "${MINGW_PREFIX}/lib" "/usr/${TARGET}/lib"

echo "==> MinGW-w64 headers installed to ${MINGW_PREFIX}/include/"
