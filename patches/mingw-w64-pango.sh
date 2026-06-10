# WHY: GIR introspection runs target .exe; documentation tools unavailable
# Disable introspection and documentation
sed -i 's/--auto-features=enabled/--auto-features=enabled -Dintrospection=disabled/' PKGBUILD
sed -i 's/-Ddocumentation=true/-Ddocumentation=false/g' PKGBUILD
# package() tries to mv share/doc which doesn't exist with docs disabled
sed -i '/mv.*share\/doc/d' PKGBUILD
