# WHY: GIR introspection runs g-ir-scanner which executes target .exe on the host
# Disable introspection (requires running target binaries)
sed -i 's|-Datk_only=true|-Datk_only=true -Dintrospection=disabled|' PKGBUILD
