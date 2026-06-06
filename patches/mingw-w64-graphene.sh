sed -i 's/-Dinstalled_tests=false/-Dinstalled_tests=false -Dintrospection=disabled/' PKGBUILD
sed -i 's/-Dgtk_doc=true/-Dgtk_doc=false/' PKGBUILD
