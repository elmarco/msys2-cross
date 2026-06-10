# WHY: Meson cross-file does not expose host nasm to the build; revisit if perf matters
# nasm is a host tool, should be found via /usr/bin/nasm
# but meson might not find it. Just disable ASM for now.
sed -i "s|-Denable_asm=true|-Denable_asm=false|" PKGBUILD
