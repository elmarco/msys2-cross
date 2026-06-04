#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 6: Final GCC ${GCC_VERSION} (C, C++)"
echo "========================================="

# Clean previous bootstrap build
rm -rf "${BUILD_DIR}/gcc-final"
mkdir -p "${BUILD_DIR}/gcc-final"
cd "${BUILD_DIR}/gcc-final"

"${SRC_DIR}/gcc-${GCC_VERSION}/configure" \
    --target="${TARGET}" \
    --prefix=/usr \
    --enable-languages=c,c++,lto \
    --enable-threads=posix \
    --enable-shared \
    --enable-static \
    --enable-libatomic \
    --enable-libgomp \
    --enable-libstdcxx-backtrace=yes \
    --enable-libstdcxx-filesystem-ts \
    --enable-libstdcxx-time \
    --enable-graphite \
    --enable-fully-dynamic-string \
    --enable-mingw-wildcard \
    --enable-checking=release \
    --enable-lto \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-multilib \
    --disable-rpath \
    --disable-nls \
    --disable-werror \
    --disable-symvers \
    --disable-win32-registry \
    --with-arch=nocona \
    --with-tune=generic \
    --with-system-zlib \
    --with-gnu-as \
    --with-gnu-ld \
    --with-pkgversion="msys2-cross cross-compiler" \
    --with-boot-ldflags="-static-libstdc++"

make -j"${JOBS}"
make install

# Install runtime DLLs into the sysroot so built packages can find them
for dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll \
           libatomic-1.dll libgomp-1.dll libquadmath-0.dll; do
    if [[ -f "/usr/${TARGET}/lib/${dll}" ]]; then
        cp -v "/usr/${TARGET}/lib/${dll}" "${MINGW_PREFIX}/bin/"
    fi
    if [[ -f "/usr/lib/gcc/${TARGET}/${GCC_VERSION}/${dll}" ]]; then
        cp -v "/usr/lib/gcc/${TARGET}/${GCC_VERSION}/${dll}" "${MINGW_PREFIX}/bin/"
    fi
done

echo "==> Final GCC ${GCC_VERSION} installed"
echo "==> Cross-compiler: ${TARGET}-gcc"
echo "==> Target sysroot: ${SYSROOT}"
