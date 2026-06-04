# glib2 calls ${MINGW_PREFIX}/bin/meson.exe — fix to use our wrapper.
# Also handles meson compile/install which don't need cross flags.
sed -i \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe setup|/opt/msys2-bootstrap/wrappers/mingw-meson|g' \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe compile|/usr/bin/meson compile|g' \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe install|/usr/bin/meson install|g' \
    PKGBUILD

# Remove MSYS2_ARG_CONV_EXCL (MSYS2-only path conversion suppression)
sed -i '/MSYS2_ARG_CONV_EXCL/d' PKGBUILD

# The package() function runs ${MINGW_PREFIX}/bin/python3 to convert
# Python scripts to .exe wrappers. Replace with host python3.
sed -i 's|${MINGW_PREFIX}/bin/python3|/usr/bin/python3|g' PKGBUILD

# Remove Windows python deps (we use host python for build-time scripts)
sed -i '/"${MINGW_PACKAGE_PREFIX}-python"$/d' PKGBUILD
sed -i '/"${MINGW_PACKAGE_PREFIX}-python-packaging"$/d' PKGBUILD
sed -i '/"${MINGW_PACKAGE_PREFIX}-python-setuptools"$/d' PKGBUILD
sed -i '/"${MINGW_PACKAGE_PREFIX}-python-docutils"$/d' PKGBUILD
