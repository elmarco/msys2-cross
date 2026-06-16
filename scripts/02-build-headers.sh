#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env-config.sh"

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

make install DESTDIR="${DESTDIR}"

# GCC cross-compiler looks for headers in /usr/<target>/include and
# libraries in /usr/<target>/lib. Binutils (stage 1) already created
# /usr/<target>/ as a real directory, so we can't replace it with a
# symlink. Instead, symlink the include and lib subdirectories into it.
#
# When DESTDIR is set (RPM/bare-host build), symlinks use staging paths
# so GCC's binary relocation resolves them during the build.
_sysroot="${DESTDIR}/usr/${TARGET}"
_prefix="${DESTDIR}${MINGW_PREFIX}"

ln -sfn "${_prefix}/include" "${_sysroot}/include"

# Move binutils' lib content (ldscripts) into the sysroot and replace
# with a symlink so GCC finds CRT libs in /usr/<target>/lib -> /ucrt64/lib
if [[ -d "${_sysroot}/lib" && ! -L "${_sysroot}/lib" ]]; then
    mkdir -p "${_prefix}/lib"
    cp -a "${_sysroot}/lib/"* "${_prefix}/lib/" 2>/dev/null || true
    rm -rf "${_sysroot}/lib"
fi
ln -sfn "${_prefix}/lib" "${_sysroot}/lib"

echo "==> MinGW-w64 headers installed to ${_prefix}/include/"
