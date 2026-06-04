# minizip links with -lz but the zlib build output isn't installed yet.
# Add -L to point at the zlib build directory.
sed -i 's|LIBS="-lbz2"|LDFLAGS="-L${srcdir}/build-${MSYSTEM}" LIBS="-lbz2 -lz"|' PKGBUILD
