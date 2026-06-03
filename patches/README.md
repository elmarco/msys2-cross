# Cross-compilation patches for MINGW-packages

Per-package patches applied automatically by `makepkg-mingw` before building.

Naming convention: `<pkgbase>.patch` (e.g., `mingw-w64-zlib.patch`).

These are applied AFTER the automatic sed rewrites in makepkg-mingw, which
handle the most common `--build=${MINGW_CHOST}` pattern. Patches here are
for cases the auto-rewrite can't handle.
