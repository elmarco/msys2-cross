# gettext 0.26: libasprintf has a double-inclusion bug with UCRT where
# lib-asprintf.c includes vasprintf.c/asprintf.c twice, causing
# redefinition errors. Disable libasprintf — we only need libintl for glib.
sed -i 's|_build "|_build "--disable-libasprintf |' PKGBUILD

# Remove MSYS2_ARG_CONV_EXCL (MSYS2-only)
sed -i '/MSYS2_ARG_CONV_EXCL/d' PKGBUILD
