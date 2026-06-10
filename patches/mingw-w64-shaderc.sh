# WHY: pacman uses separate DB path in cross env; cygpath does not exist on Linux; asciidoctor path differs
# The prepare() uses `pacman -Q` to query spirv-tools and glslang versions
# for build-version.inc. Replace with hardcoded version strings since our
# pacman DB uses a different config path.
sed -i 's|$(pacman -Q "${MINGW_PACKAGE_PREFIX}-spirv-tools"|$(pacman --config /opt/msys2-cross/config/pacman-mingw.conf -Q "${MINGW_PACKAGE_PREFIX}-spirv-tools"|g' PKGBUILD
sed -i 's|$(pacman -Q "${MINGW_PACKAGE_PREFIX}-glslang"|$(pacman --config /opt/msys2-cross/config/pacman-mingw.conf -Q "${MINGW_PACKAGE_PREFIX}-glslang"|g' PKGBUILD

# cygpath call for glslang include dir
sed -i 's|cygpath -m "${MINGW_PREFIX}/include/glslang"|echo "${MINGW_PREFIX}/include/glslang"|g' PKGBUILD

# asciidoctor is at /usr/bin/asciidoctor on host
sed -i 's|${MINGW_PREFIX}/bin/asciidoctor|/usr/bin/asciidoctor|g' PKGBUILD
