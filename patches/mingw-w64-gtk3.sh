# Disable introspection and man pages (require running target binaries)
sed -i 's|--auto-features=enabled|--auto-features=enabled -Dintrospection=false -Dman=false|' PKGBUILD
# Replace explicit -Dman=true with false (can't delete — breaks if/fi block)
sed -i 's/-Dman=true/-Dman=false/' PKGBUILD
# Use native gtk-update-icon-cache (cache format is host-agnostic)
sed -i 's|mv "${pkgdir}"${MINGW_PREFIX}/bin/gtk-update-icon-cache "$srcdir"|rm -f "${pkgdir}"${MINGW_PREFIX}/bin/gtk-update-icon-cache*; cp /usr/bin/gtk-update-icon-cache "$srcdir"/gtk-update-icon-cache|' PKGBUILD
# Man pages not generated (disabled with -Dman=false)
sed -i 's|mv "${pkgdir}"${MINGW_PREFIX}/share/man/man1/gtk-update-icon-cache.1|true #|' PKGBUILD
sed -i 's|install -Dt "${pkgdir}${MINGW_PREFIX}/share/man/man1" gtk-update-icon-cache.1|true #|' PKGBUILD
# The cp {,-3.0}.exe brace expansion won't work with native binary — replace with simple cp
sed -i 's|cp "${pkgdir}"${MINGW_PREFIX}/bin/gtk-update-icon-cache{,-3.0}.exe|cp "${pkgdir}"${MINGW_PREFIX}/bin/gtk-update-icon-cache "${pkgdir}"${MINGW_PREFIX}/bin/gtk-update-icon-cache-3.0|' PKGBUILD
