# Disable introspection entirely (both static and shared)
sed -i 's/-Dintrospection=disabled/-Dintrospection=disabled/' PKGBUILD
# Also disable in shared build (which doesn't have the flag)
sed -i 's/--default-library=shared/--default-library=shared -Dintrospection=disabled/' PKGBUILD
