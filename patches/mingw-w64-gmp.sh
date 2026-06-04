# GMP cross-compilation is broken without Wine:
# Its configure scans compiled object files assuming ELF format,
# but the cross-compiler produces PE/COFF (Windows) objects.
# The "long long reliability test" fails because `od` patterns don't match.
#
# Fixes: install Wine and enable binfmt_misc, or use Fedora's mingw64-gmp
# patches that handle PE/COFF objects.
#
# For now, disable assembly to at least avoid assembly-specific failures.
sed -i 's/--enable-fat/--disable-assembly/' PKGBUILD
