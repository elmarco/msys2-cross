# WHY: Linux is case-sensitive; GitHub archive extracts as xxHash-* not xxhash-*
# GitHub archive extracts to xxHash-0.8.3 (capital H) but PKGBUILD
# references xxhash-0.8.3 (lowercase). Case-insensitive on MSYS2, fails on Linux.
cat >> PKGBUILD << 'PATCH'
prepare() {
  [[ -d "${srcdir}/${_realname}-${pkgver}" ]] || \
    mv "${srcdir}"/xxHash-${pkgver} "${srcdir}/${_realname}-${pkgver}" 2>/dev/null || true
}
PATCH
