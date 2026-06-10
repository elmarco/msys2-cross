# WHY: GIR runs g-ir-scanner .exe; pyscript2exe needs Windows Python; replace Python deps
# GIR needs g-ir-scanner (.exe)
sed -i 's/_enable_gir=yes/_enable_gir=no/' PKGBUILD

# pyscript2exe converts Python scripts to .exe wrappers — skip
sed -i 's|for name in glib-mkenums.*|for name in; do  # pyscript2exe disabled|' PKGBUILD

# Windows python deps → already-installed cc (preserves array syntax)
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python-packaging"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python-docutils"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
sed -i '/"${MINGW_PACKAGE_PREFIX}-python-setuptools"/d' PKGBUILD
