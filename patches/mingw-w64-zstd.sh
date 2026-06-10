# WHY: Build runs gen_html.exe to produce docs; cross-compiled .exe cannot run on Linux
# zstd builds gen_html.exe and tries to run it to generate docs.
# Cross-compiled .exe can't run on Linux. Disable doc generation.
sed -i 's/-DZSTD_BUILD_CONTRIB=ON/-DZSTD_BUILD_CONTRIB=OFF/' PKGBUILD
