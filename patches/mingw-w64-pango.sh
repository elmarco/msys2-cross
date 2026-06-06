# Disable introspection in shared build
sed -i '/-Ddefault_library=shared/a\    -Dintrospection=disabled \\' PKGBUILD
