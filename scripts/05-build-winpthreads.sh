#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env-config.sh"

echo "========================================="
echo "Stage 5: winpthreads ${MINGW_W64_VERSION}"
echo "========================================="

if [[ ! -d "${SRC_DIR}/mingw-w64" ]]; then
    download_and_extract "${MINGW_W64_URL}" "${SRC_DIR}/mingw-w64"
fi

mkdir -p "${BUILD_DIR}/winpthreads"
cd "${BUILD_DIR}/winpthreads"

if [[ "${CC_FAMILY}" = "clang" ]]; then
    export CC="${CROSS_CC}"
    export CXX="${CROSS_CXX}"
    export AR="${CROSS_AR}"
    export RANLIB="${CROSS_RANLIB}"
    export DLLTOOL="${CROSS_DLLTOOL}"
    export WINDRES="${CROSS_WINDRES}"
    export RC="${CROSS_WINDRES}"
fi

"${SRC_DIR}/mingw-w64/mingw-w64-libraries/winpthreads/configure" \
    --host="${TARGET}" \
    --prefix="${MINGW_PREFIX}" \
    --enable-static \
    --enable-shared

make -j"${JOBS}"
make install DESTDIR="${DESTDIR}"

echo "==> winpthreads installed to ${DESTDIR}${MINGW_PREFIX}/"
