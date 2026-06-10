# WHY: GIR introspection runs target .exe; gtk-doc toolchain unavailable
sed -i 's/-Dinstalled_tests=false/-Dinstalled_tests=false -Dintrospection=disabled/' PKGBUILD
sed -i 's/-Dgtk_doc=true/-Dgtk_doc=false/' PKGBUILD
