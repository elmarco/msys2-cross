# WHY: docbook2man is not available in the cross-compilation container
# Disable manpage/docs generation (docbook2man not available)
# Expat uses cmake — add the flag to the cmake invocation
sed -i 's|-DEXPAT_BUILD_EXAMPLES=OFF|-DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_DOCS=OFF|' PKGBUILD
# If the flag isn't there, append it after BUILD_TESTS
sed -i 's|-DEXPAT_BUILD_TESTS=OFF|-DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_DOCS=OFF|' PKGBUILD
