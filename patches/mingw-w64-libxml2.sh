# --build="${MINGW_CHOST}" (with quotes) isn't caught by the generic sed
sed -i 's|--build="${MINGW_CHOST}"|--build=x86_64-redhat-linux|g' PKGBUILD
# Disable python in shared build (Windows python not available)
sed -i 's|--with-python|--without-python|g' PKGBUILD
