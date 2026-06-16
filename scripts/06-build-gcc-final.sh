#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env-config.sh"

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
    --with-sysroot="/usr/${TARGET}" \
    --with-native-system-header-dir=/include \
    ${DESTDIR:+--with-build-sysroot="${DESTDIR}/usr/${TARGET}"} \
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

if [[ -n "${DESTDIR}" ]]; then
    # GCC's generated Makefile has FLAGS_FOR_TARGET with make-variable paths
    # like ${prefix}/${target} and $(build_tooldir) that resolve to the final
    # install prefix (/usr/x86_64-w64-mingw32) — which doesn't exist during a
    # DESTDIR build. Rewrite these variables' definitions so paths point into
    # the staging directory instead.
    _dt="${DESTDIR}/usr/${TARGET}"
    sed -i 's|^build_tooldir = .*|build_tooldir = '"${_dt}"'|
            s|^tooldir = .*|tooldir = '"${_dt}"'|' Makefile
    sed -i '/^FLAGS_FOR_TARGET/s|\${prefix}/\${target}|'"${_dt}"'|g
            /^FLAGS_FOR_TARGET/s|\${prefix}/mingw|'"${DESTDIR}"'/usr/mingw|g' Makefile
fi
make -j"${JOBS}"
make install DESTDIR="${DESTDIR}"

# Install runtime DLLs into the sysroot so built packages can find them
_prefix="${DESTDIR}${MINGW_PREFIX}"
mkdir -p "${_prefix}/bin"
for dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll \
           libatomic-1.dll libgomp-1.dll libquadmath-0.dll; do
    if [[ -f "${DESTDIR}/usr/${TARGET}/lib/${dll}" ]]; then
        cp -v "${DESTDIR}/usr/${TARGET}/lib/${dll}" "${_prefix}/bin/"
    fi
    # Fedora uses lib64, other distros may use lib
    for libdir in lib64 lib; do
        if [[ -f "${DESTDIR}/usr/${libdir}/gcc/${TARGET}/${GCC_VERSION}/${dll}" ]]; then
            cp -v "${DESTDIR}/usr/${libdir}/gcc/${TARGET}/${GCC_VERSION}/${dll}" "${_prefix}/bin/"
        fi
    done
done

echo "==> Final GCC ${GCC_VERSION} installed"
echo "==> Cross-compiler: ${TARGET}-gcc"
echo "==> Target sysroot: ${SYSROOT}"
