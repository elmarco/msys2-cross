# Disable libasprintf (UCRT double-inclusion bug)
sed -i 's|_build "|_build "--disable-libasprintf |' PKGBUILD
