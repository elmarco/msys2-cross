#!/bin/bash
set -euo pipefail

# Extra host tools needed for building MINGW packages.
# These are the native equivalents of the dummy pacman packages.
# Changes here do NOT invalidate the toolchain cache.
dnf install -y \
    --setopt=install_weak_deps=False \
    --setopt=keepcache=False \
    --setopt=tsflags=nodocs \
    --setopt=max_parallel_downloads=10 \
    --setopt=fastestmirror=True \
    \
    python3-devel python3-pip \
    python3-docutils python3-sphinx python3-lxml \
    python3-setuptools python3-numpy python3-jinja2 \
    python3-pygments python3-babel python3-packaging \
    python3-markupsafe python3-mako python3-fonttools \
    python3-cython \
    \
    perl ruby rubygem-asciidoctor \
    doxygen graphviz swig vala \
    gtk-doc itstool \
    po4a nasm ragel \
    groff autoconf-archive xmlto \
    \
    gtk-update-icon-cache \
    \
    cargo-c

# Symlink host-agnostic tools into MINGW_PREFIX so PKGBUILDs find them without Wine
mkdir -p /ucrt64/bin
ln -sf /usr/bin/gtk-update-icon-cache /ucrt64/bin/gtk-update-icon-cache

dnf clean all
