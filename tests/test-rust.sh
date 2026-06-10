#!/bin/bash
set -euo pipefail

# Smoke test: cross-compile a Rust project for Windows.
# Validates that the Rust std library (built from source in stage 09)
# works correctly with cargo/rustc targeting x86_64-pc-windows-gnu.
# Run inside the msys2-cross container.

echo "=== Test: Rust cross-compilation ==="

WORKDIR=$(mktemp -d)
trap "rm -rf ${WORKDIR}" EXIT

RUST_TARGET=x86_64-pc-windows-gnu

# --- Check Rust toolchain ---
echo "--- Checking Rust tools ---"
if ! command -v rustc &>/dev/null; then
    echo "FAIL: rustc not found"
    exit 1
fi
if ! command -v cargo &>/dev/null; then
    echo "FAIL: cargo not found"
    exit 1
fi
echo "  rustc: $(rustc --version)"
echo "  cargo: $(cargo --version)"

# Verify the cross std library exists
RUST_SYSROOT=$(rustc --print sysroot)
STD_DIR="${RUST_SYSROOT}/lib/rustlib/${RUST_TARGET}/lib"
if [[ ! -d "${STD_DIR}" ]]; then
    echo "FAIL: Rust std library not found at ${STD_DIR}"
    exit 1
fi
if ! ls "${STD_DIR}"/libstd-*.rlib &>/dev/null; then
    echo "FAIL: No libstd-*.rlib in ${STD_DIR}"
    ls -la "${STD_DIR}/"
    exit 1
fi
echo "PASS: Rust std library present for ${RUST_TARGET}"

# --- Simple rustc compilation ---
echo "--- Testing rustc direct compilation ---"
cat > "${WORKDIR}/hello.rs" << 'RSRC'
fn main() {
    println!("Hello from cross-compiled Rust!");
    let v: Vec<i32> = (1..=5).collect();
    println!("Sum: {}", v.iter().sum::<i32>());
}
RSRC

rustc --target "${RUST_TARGET}" -o "${WORKDIR}/hello.exe" "${WORKDIR}/hello.rs"
if ! file "${WORKDIR}/hello.exe" | grep -q "PE32+"; then
    echo "FAIL: hello.exe is not a PE32+ binary"
    file "${WORKDIR}/hello.exe"
    exit 1
fi
echo "PASS: rustc cross-compilation produces PE32+"

# --- Cargo project ---
echo "--- Testing cargo build ---"
mkdir -p "${WORKDIR}/myproject/src"
cat > "${WORKDIR}/myproject/Cargo.toml" << 'TOML'
[package]
name = "hello-cross"
version = "0.1.0"
edition = "2021"
TOML

cat > "${WORKDIR}/myproject/src/main.rs" << 'RSRC'
use std::collections::HashMap;

fn main() {
    let mut map = HashMap::new();
    map.insert("language", "Rust");
    map.insert("target", "Windows");
    for (k, v) in &map {
        println!("{}: {}", k, v);
    }
}
RSRC

cd "${WORKDIR}/myproject"
cargo build --target "${RUST_TARGET}" 2>&1
BINARY="${WORKDIR}/myproject/target/${RUST_TARGET}/debug/hello-cross.exe"
if [[ ! -f "${BINARY}" ]]; then
    echo "FAIL: cargo build did not produce ${BINARY}"
    find "${WORKDIR}/myproject/target" -name "*.exe" 2>/dev/null
    exit 1
fi
if ! file "${BINARY}" | grep -q "PE32+"; then
    echo "FAIL: hello-cross.exe is not a PE32+ binary"
    file "${BINARY}"
    exit 1
fi
echo "PASS: cargo build produces PE32+ executable"

echo ""
echo "=== All Rust tests passed ==="
