# Disable Python bindings (Windows python not available for cross-compilation)
sed -i "s|'-DBOOST_ENABLE_PYTHON=ON'|'-DBOOST_ENABLE_PYTHON=OFF'|g" PKGBUILD
