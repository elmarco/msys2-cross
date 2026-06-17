# Exclude LLVM runtime libs from CRT — packaged in cross-clang
sed -i '/rm -f.*libgcc/a\
    rm -f "${pkgdir}"'"${MINGW_PREFIX}"'/lib/libc++* 2>/dev/null || true\
    rm -f "${pkgdir}"'"${MINGW_PREFIX}"'/lib/libunwind* 2>/dev/null || true' \
    PKGBUILD
