# glib2 calls ${MINGW_PREFIX}/bin/meson.exe — fix to use our wrapper.
sed -i \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe setup|/opt/msys2-bootstrap/wrappers/mingw-meson|g' \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe compile|/usr/bin/meson compile|g' \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe install|/usr/bin/meson install|g' \
    PKGBUILD

# Remove MSYS2_ARG_CONV_EXCL (MSYS2-only path conversion suppression)
sed -i '/MSYS2_ARG_CONV_EXCL/d' PKGBUILD

# Disable gobject-introspection (needs g-ir-scanner which runs .exe)
sed -i 's/_enable_gir=yes/_enable_gir=no/' PKGBUILD

# Remove noextract — let makepkg handle extraction normally.
# The PKGBUILD uses noextract + manual tar in prepare() to work around
# MSYS2 path issues, but on Linux standard extraction works fine.
sed -i '/^noextract/d' PKGBUILD
sed -i '/tar -xf.*glib.*tar/d' PKGBUILD

# The package() function runs pyscript2exe.py to convert Python scripts
# into .exe wrappers via a for loop. Replace the loop with a no-op.
sed -i 's|for name in glib-mkenums.*|for name in; do  # pyscript2exe loop disabled|' PKGBUILD

# Remove Windows-only deps by replacing with the cross-compiler dep
# (which is already present). This avoids deleting array lines or
# leaving empty values. Safe because these are whole-line entries.
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python-packaging"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i '/"${MINGW_PACKAGE_PREFIX}-python-setuptools"/d' PKGBUILD

# python-docutils has the closing ) — replace content but keep the line
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python-docutils"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD

# gettext-tools: replace, don't delete (might be last in subarray)
sed -i 's|"${MINGW_PACKAGE_PREFIX}-gettext-tools"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
