# meson.exe → our wrappers
sed -i \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe setup|/opt/msys2-cross/wrappers/mingw-meson|g' \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe compile|/usr/bin/meson compile|g' \
    -e 's|${MINGW_PREFIX}/bin/meson\.exe install|/usr/bin/meson install|g' \
    PKGBUILD

# MSYS2-only env var
sed -i '/MSYS2_ARG_CONV_EXCL/d' PKGBUILD

# GIR needs g-ir-scanner (.exe)
sed -i 's/_enable_gir=yes/_enable_gir=no/' PKGBUILD

# noextract + manual tar is an MSYS2 path workaround
sed -i '/^noextract/d' PKGBUILD
sed -i '/tar -xf.*glib.*tar/d' PKGBUILD

# pyscript2exe converts Python scripts to .exe wrappers — skip
sed -i 's|for name in glib-mkenums.*|for name in; do  # pyscript2exe disabled|' PKGBUILD

# Windows python deps → already-installed cc (preserves array syntax)
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python-packaging"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python-docutils"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i '/"${MINGW_PACKAGE_PREFIX}-python-setuptools"/d' PKGBUILD
