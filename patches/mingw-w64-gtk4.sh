# WHY: GIR/man/glslc run target .exe; directx-headers not implicit in cross env; gstreamer too complex
# Add directx-headers makedep (on MSYS2 these come from mingw-w64-headers, cross needs explicit package)
sed -i '/makedepends=/a\             "${MINGW_PACKAGE_PREFIX}-directx-headers"' PKGBUILD
# Disable introspection (requires running target binaries)
sed -i 's|-Dintrospection=enabled|-Dintrospection=disabled|' PKGBUILD
# Disable man pages (requires rst2man on target)
sed -i 's|-Dman-pages=true|-Dman-pages=false|' PKGBUILD
# Disable gstreamer media backend (complex dep chain)
sed -i 's|-Dmedia-gstreamer=enabled|-Dmedia-gstreamer=disabled|' PKGBUILD
# Remove gst-plugins-bad-libs from depends (gstreamer disabled)
sed -i '/gst-plugins-bad-libs/d' PKGBUILD
# Disable Vulkan renderer (glslc shader compiler not available)
sed -i 's|-Dvulkan=enabled|-Dvulkan=disabled|' PKGBUILD
