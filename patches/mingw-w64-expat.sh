# Disable manpage generation (docbook2man not available)
sed -i 's/-DEXPAT_BUILD_DOCS=ON/-DEXPAT_BUILD_DOCS=OFF/' PKGBUILD
