# WHY: Dictionary generation tool runs as target .exe; dictionaries not needed for library linkage
sed -i 's|--enable-shared|--enable-shared --disable-dict|' PKGBUILD
