#!/bin/bash
set -euo pipefail

# Create the Source10 tarball (build infrastructure) for rpmbuild.
#
# Usage: ./scripts/make-srpm-sources.sh [output-dir]
#
# When output-dir already contains toolchain tarballs (e.g. from spectool),
# only the scripts tarball is created. Otherwise, symlinks to sources/ are
# added so rpmbuild can find everything.
#
# Then build with:
#   rpmbuild -bs msys2-cross.spec --define "_sourcedir <output-dir>"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
source "${SCRIPT_DIR}/common.sh"

OUTDIR="${1:-${REPO_DIR}/rpmbuild-sources}"
mkdir -p "${OUTDIR}"
OUTDIR="$(cd "${OUTDIR}" && pwd)"

# Pack build infrastructure (scripts, config, wrappers, patches, packages)
TARNAME="msys2-cross-scripts-${GCC_VERSION}.tar.gz"
echo "==> Creating ${TARNAME}..."
tar czf "${OUTDIR}/${TARNAME}" \
    -C "${REPO_DIR}" \
    scripts/ config/ wrappers/ patches/ packages/

# Link toolchain source tarballs (skip if output dir is sources/ itself,
# or if the tarballs are already present — e.g. from spectool in COPR)
SOURCES_DIR="$(cd "${REPO_DIR}/sources" 2>/dev/null && pwd || true)"
if [[ -n "${SOURCES_DIR}" && "${OUTDIR}" != "${SOURCES_DIR}" ]]; then
    echo "==> Linking toolchain sources..."
    for src in "${SOURCES_DIR}"/*; do
        [ -f "$src" ] || continue
        dest="${OUTDIR}/$(basename "$src")"
        [ -e "$dest" ] && continue
        ln -sfn "$(realpath "$src")" "$dest"
    done
fi

echo ""
echo "==> Sources ready in ${OUTDIR}/"
ls -lh "${OUTDIR}/"
echo ""
echo "Build SRPM with:"
echo "  rpmbuild -bs msys2-cross.spec --define '_sourcedir ${OUTDIR}'"
