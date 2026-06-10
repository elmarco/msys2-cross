#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "========================================="
echo "Stage 9: Build Rust std for mingw target"
echo "========================================="

RUST_SRC_DIR="${SRC_DIR}/rustc-${RUST_VERSION}-src"
RUST_SYSROOT=$(rustc --print sysroot)
RUST_TARGET=x86_64-pc-windows-gnu

echo "==> Bootstrap rustc: $(rustc --version)"
echo "==> Target: ${TARGET} (${RUST_TARGET})"
echo "==> Sysroot: ${RUST_SYSROOT}"

# Extract Rust source
download_and_extract "${RUST_SRC_URL}" "${RUST_SRC_DIR}"

cd "${RUST_SRC_DIR}"

# Configure the Rust build system to cross-compile std only.
# --stage 0 means: use Fedora's rustc directly (not a freshly built one).
# local-rebuild: the source version must match the installed rustc exactly.
cat > config.toml << EOF
[build]
build = "x86_64-unknown-linux-gnu"
host = []
target = ["${RUST_TARGET}"]
docs = false
extended = false
tools = []
cargo = "$(which cargo)"
rustc = "$(which rustc)"
local-rebuild = true

[llvm]
download-ci-llvm = false

[rust]
channel = "stable"

[target.${RUST_TARGET}]
cc = "${TARGET}-gcc"
cxx = "${TARGET}-g++"
ar = "${TARGET}-ar"
ranlib = "${TARGET}-ranlib"
linker = "${TARGET}-gcc"
EOF

# x.py queries git log for version info — create a stub repo
git init -q . 2>/dev/null || true
git add config.toml 2>/dev/null || true
git -c user.email=b@b -c user.name=b commit -qm "v${RUST_VERSION}" 2>/dev/null || true

# Build std for the cross target using stage 0 (Fedora's rustc).
echo "==> Building Rust std library for ${RUST_TARGET}..."
python3 x.py build library --target "${RUST_TARGET}" --stage 0 -j"${JOBS}"

# Locate the built libraries dynamically (output path varies by Rust version).
echo "==> Locating built artifacts..."
PROBE=$(find "${RUST_SRC_DIR}/build" -name "libstd-*.rlib" -path "*/${RUST_TARGET}/*" | head -1)
if [[ -z "${PROBE}" ]]; then
    echo "==> ERROR: Cannot find libstd-*.rlib for ${RUST_TARGET}"
    echo "==> Build tree contents:"
    find "${RUST_SRC_DIR}/build" -path "*/${RUST_TARGET}*" -type d 2>/dev/null | head -20
    exit 1
fi
BUILT_LIBS=$(dirname "${PROBE}")
echo "==> Found artifacts in: ${BUILT_LIBS}"
echo "==> Artifact count: $(ls "${BUILT_LIBS}"/*.rlib 2>/dev/null | wc -l) rlib files"

# Install into the host rustc sysroot
DEST="${RUST_SYSROOT}/lib/rustlib/${RUST_TARGET}/lib"
mkdir -p "${DEST}"
cp -a "${BUILT_LIBS}"/*.rlib "${DEST}/"
cp -a "${BUILT_LIBS}"/*.rmeta "${DEST}/" 2>/dev/null || true
cp -a "${BUILT_LIBS}"/*.so "${DEST}/" 2>/dev/null || true
cp -a "${BUILT_LIBS}"/*.dll.a "${DEST}/" 2>/dev/null || true

# Verify the install
TOTAL_INSTALLED=$(ls "${DEST}"/*.rlib 2>/dev/null | wc -l)
if ! ls "${DEST}"/libstd-*.rlib &>/dev/null; then
    echo "==> ERROR: No libstd rlib installed to ${DEST}"
    exit 1
fi
echo "==> Installed ${TOTAL_INSTALLED} rlib files to ${DEST}"

# Verify cross-compilation works
echo "==> Verifying Rust cross-compilation..."
TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/hello.rs" << 'EOF'
fn main() { println!("Hello from cross-compiled Rust!"); }
EOF
rustc --target "${RUST_TARGET}" "${TMPDIR}/hello.rs" -o "${TMPDIR}/hello.exe"
echo "==> Rust cross-compilation verified: $(file "${TMPDIR}/hello.exe")"
rm -rf "${TMPDIR}"

# Clean up build artifacts to keep layer size small
rm -rf "${RUST_SRC_DIR}" "${BUILD_DIR}" "${SRC_DIR}"

echo "==> Rust cross-toolchain ready"
echo "    rustc $(rustc --version)"
echo "    Target: ${RUST_TARGET}"
echo "    Sysroot: ${DEST}"
