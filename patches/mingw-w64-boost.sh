# WHY: Cross-compiled Windows Python interpreter is not available on Linux host
# Disable Python bindings (Windows python not available for cross-compilation)
sed -i "s|'-DBOOST_ENABLE_PYTHON=ON'|'-DBOOST_ENABLE_PYTHON=OFF'|g" PKGBUILD
