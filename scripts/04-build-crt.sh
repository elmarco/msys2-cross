#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env-config.sh"

echo "========================================="
echo "Stage 4: MinGW-w64 CRT ${MINGW_W64_VERSION}"
echo "========================================="

# mingw-w64 source already downloaded in stage 2
if [[ ! -d "${SRC_DIR}/mingw-w64" ]]; then
    download_and_extract "${MINGW_W64_URL}" "${SRC_DIR}/mingw-w64"
fi

mkdir -p "${BUILD_DIR}/crt"
cd "${BUILD_DIR}/crt"

if [[ "${CC_FAMILY}" = "clang" ]]; then
    export CC="${CROSS_CC}"
    export CXX="${CROSS_CXX}"
    export AR="${CROSS_AR}"
    export RANLIB="${CROSS_RANLIB}"
    export DLLTOOL="${CROSS_DLLTOOL}"
fi

_crt_lib_flags=""
case "${CMAKE_SYSTEM_PROCESSOR}" in
    x86_64)  _crt_lib_flags="--enable-lib64 --disable-lib32" ;;
    aarch64) _crt_lib_flags="--enable-libarm64 --disable-lib32 --disable-lib64" ;;
esac

"${SRC_DIR}/mingw-w64/mingw-w64-crt/configure" \
    --host="${TARGET}" \
    --prefix="${MINGW_PREFIX}" \
    --with-default-msvcrt=ucrt \
    ${_crt_lib_flags} \
    --enable-static \
    --enable-shared

make -j"${JOBS}"
make install DESTDIR="${DESTDIR}"

echo "==> MinGW-w64 CRT installed to ${DESTDIR}${MINGW_PREFIX}/lib/"
