# GIR disabled in static build already; also disable in shared
sed -i '/-Ddefault_library=shared/a\    -Dintrospection=disabled \\' PKGBUILD
# Python deps for pyscript2exe
sed -i 's|"${MINGW_PACKAGE_PREFIX}-python"|"${MINGW_PACKAGE_PREFIX}-cc"|' PKGBUILD
