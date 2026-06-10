#!/bin/bash
set -euo pipefail

# Minimal deps for building the cross-toolchain (stages 01-06).
# Changes here invalidate the toolchain cache — keep this stable.
# Uses dnf intentionally — the Containerfile pins Fedora as the base image.
dnf install -y \
    --setopt=install_weak_deps=False \
    --setopt=keepcache=False \
    --setopt=tsflags=nodocs \
    --setopt=max_parallel_downloads=10 \
    --setopt=fastestmirror=True \
    \
    gcc gcc-c++ make cmake ninja-build meson \
    autoconf automake libtool \
    texinfo bison flex gperf \
    patch git curl \
    gmp-devel mpfr-devel libmpc-devel isl-devel \
    zlib-devel readline-devel \
    diffutils findutils file which \
    tar xz bzip2 zstd \
    pacman fakeroot \
    python3

dnf clean all
