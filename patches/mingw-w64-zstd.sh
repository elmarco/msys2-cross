# zstd builds gen_html.exe and tries to run it to generate docs.
# Cross-compiled .exe can't run on Linux. Disable doc generation.
sed -i 's/-DZSTD_BUILD_CONTRIB=ON/-DZSTD_BUILD_CONTRIB=OFF/' PKGBUILD
