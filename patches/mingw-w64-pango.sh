# Disable introspection
sed -i 's/--auto-features=enabled/--auto-features=enabled -Dintrospection=disabled/' PKGBUILD
