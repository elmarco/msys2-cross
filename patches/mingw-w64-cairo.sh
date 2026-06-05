# Windows python deps → host python handles fonttools
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python-fonttools"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD

# Disable lzo2 — type mismatch (lzo_uint* vs uLongf*) in cross-compilation
sed -i 's|-Dsymbol-lookup=disabled|-Dsymbol-lookup=disabled -Dlzo=disabled|' PKGBUILD
