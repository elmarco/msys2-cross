# WHY: GIR introspection runs g-ir-scanner which executes target .exe on the host
sed -i 's/--auto-features=enabled/--auto-features=enabled -Dintrospection=disabled/' PKGBUILD
