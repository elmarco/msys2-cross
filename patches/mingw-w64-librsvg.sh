# WHY: container is offline — crates come from the host's pre-fetched cargo registry
sed -i '/cargo update/d; /cargo fetch/d' PKGBUILD
# WHY: vapigen (Vala) not available; GIR runs target .exe; docs need gi-docgen
# Disable Vala bindings in both static and shared builds (vapigen not available)
sed -i 's|--auto-features=enabled|& -Dvala=disabled|' PKGBUILD
# Disable introspection, docs, and pixbuf-loader in shared build
sed -i 's|-Dpixbuf-loader=enabled|-Dpixbuf-loader=disabled -Dintrospection=disabled -Ddocs=disabled|' PKGBUILD
# Skip doc split-package (docs disabled)
sed -i 's|mv "${pkgdir}${MINGW_PREFIX}"/share/doc|true #|' PKGBUILD
