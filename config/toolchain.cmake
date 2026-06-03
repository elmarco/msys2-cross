# CMake toolchain file for UCRT64 cross-compilation from Linux.
# Can be used directly: cmake -DCMAKE_TOOLCHAIN_FILE=.../toolchain.cmake
# The mingw-cmake wrapper is preferred for PKGBUILD compatibility.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(TARGET x86_64-w64-mingw32)
set(MINGW_PREFIX /ucrt64)

set(CMAKE_C_COMPILER ${TARGET}-gcc)
set(CMAKE_CXX_COMPILER ${TARGET}-g++)
set(CMAKE_RC_COMPILER ${TARGET}-windres)

set(CMAKE_AR /usr/bin/${TARGET}-ar CACHE FILEPATH "Archiver")
set(CMAKE_RANLIB /usr/bin/${TARGET}-ranlib CACHE FILEPATH "Ranlib")

set(CMAKE_FIND_ROOT_PATH ${MINGW_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_INSTALL_PREFIX ${MINGW_PREFIX} CACHE PATH "Install prefix")
