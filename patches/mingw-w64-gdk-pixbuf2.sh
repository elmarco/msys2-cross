# WHY: GIR runs target .exe; gi-docgen unavailable; Windows Python not available
# Disable introspection and docs (gi-docgen not available)
sed -i 's|--auto-features=enabled|--auto-features=enabled -Dintrospection=disabled|' PKGBUILD
sed -i 's|-Ddocumentation=true|-Ddocumentation=false|g' PKGBUILD
sed -i '/mv.*share\/doc/d' PKGBUILD
# Python deps for pyscript2exe
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
