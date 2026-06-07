#!/bin/bash
set -euo pipefail

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
    \
    python3 python3-devel python3-pip \
    python3-docutils python3-sphinx python3-lxml \
    python3-setuptools python3-numpy python3-jinja2 \
    python3-pygments python3-babel python3-packaging \
    python3-markupsafe python3-mako python3-fonttools \
    python3-cython \
    \
    perl ruby \
    doxygen graphviz swig vala \
    gtk-doc itstool \
    po4a \
    nasm \
    ragel \
    \
    gtk-update-icon-cache

dnf clean all
