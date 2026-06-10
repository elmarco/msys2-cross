# WHY: gtkdocize/gtk-doc toolchain not available in cross environment
# gtkdocize not available — disable gtk-doc
sed -i 's/--enable-gtk-doc/--disable-gtk-doc/' PKGBUILD
# Skip gtkdocize in autoreconf
sed -i 's/gtkdocize/true/' PKGBUILD
