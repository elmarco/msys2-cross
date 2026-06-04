#!/bin/bash
set -euo pipefail

dnf install -y \
    --setopt=install_weak_deps=False \
    --setopt=keepcache=False \
    --setopt=tsflags=nodocs \
    --setopt=max_parallel_downloads=10 \
    --setopt=fastestmirror=True \
    gcc gcc-c++ make cmake ninja-build meson \
    python3 python3-devel \
    autoconf automake libtool \
    texinfo bison flex gperf \
    patch git curl \
    gmp-devel mpfr-devel libmpc-devel isl-devel \
    zlib-devel \
    diffutils findutils file which \
    tar xz bzip2 zstd \
    pacman fakeroot \
    perl po4a doxygen

dnf clean all
