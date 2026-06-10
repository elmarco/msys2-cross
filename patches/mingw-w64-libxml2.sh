# WHY: Quoted --build= not caught by generic rewrite; Windows Python unavailable; xsltproc missing for docs
# --build="${MINGW_CHOST}" (with quotes) isn't caught by the generic sed
sed -i "s|--build=\"\${MINGW_CHOST}\"|--build=$(gcc -dumpmachine)|g" PKGBUILD
# Disable python in shared build (Windows python not available)
sed -i 's|--with-python|--without-python|g' PKGBUILD
# Remove python compileall in package() — no python bindings installed
sed -i '/python.*-m.*compileall/,/python"\*/d' PKGBUILD
# Disable docs sub-package build (needs xsltproc + docbook)
sed -i 's|--with-docs|--without-docs|g' PKGBUILD
# package_libxml2() tries to mv share/doc which doesn't exist with --without-docs
sed -i '/mv.*share\/doc/d' PKGBUILD
