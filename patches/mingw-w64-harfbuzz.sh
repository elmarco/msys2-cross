sed -i 's/-Dintrospection=enabled/-Dintrospection=disabled/g' PKGBUILD
sed -i 's/-Dicu=enabled/-Dicu=disabled/g' PKGBUILD
sed -i 's/"-Dicu=enabled"/"-Dicu=disabled"/g' PKGBUILD
sed -i 's/-Dchafa=enabled/-Dchafa=disabled/g' PKGBUILD
sed -i 's/"-Dchafa=enabled"/"-Dchafa=disabled"/g' PKGBUILD
# Replace icu/chafa deps with already-installed packages (preserve array structure)
sed -i 's/"${MINGW_PACKAGE_PREFIX}-icu"/"${MINGW_PACKAGE_PREFIX}-cc"/g' PKGBUILD
sed -i 's/"${MINGW_PACKAGE_PREFIX}-chafa"/"${MINGW_PACKAGE_PREFIX}-cc"/g' PKGBUILD
# Neutralize icu-related file operations in package() — use || true
sed -i 's|mv "${pkgdir}"${MINGW_PREFIX}/bin/libharfbuzz-icu|true #&|' PKGBUILD
sed -i 's|mv "${pkgdir}"${MINGW_PREFIX}/include/harfbuzz/hb-icu|true #&|' PKGBUILD
sed -i 's|mv "${pkgdir}"${MINGW_PREFIX}/lib/libharfbuzz-icu|true #&|' PKGBUILD
sed -i 's|mv "${pkgdir}"${MINGW_PREFIX}/lib/pkgconfig/harfbuzz-icu|true #&|' PKGBUILD
# Make harfbuzz-icu package function a no-op (split package still listed but empty)
sed -i 's|package_harfbuzz-icu() {|package_harfbuzz-icu() { true; return; |' PKGBUILD
