#!/usr/bin/env bash
# Installs the MINGW64 packages the app needs (mirrors .github/workflows/build-msys2.yml).
# If pacman updates itself it closes the shell; just run this again.
set -euo pipefail
pacman -Syu --noconfirm
P=mingw-w64-x86_64
pacman -S --needed --noconfirm git diffutils make unzip zip \
  $P-ca-certificates $P-cc $P-cmake $P-curl $P-fast_float $P-fftw $P-json-c \
  $P-libevent $P-lcms2 $P-libdovi $P-meson $P-miniupnpc $P-gcc $P-nasm $P-ninja \
  $P-openssl $P-opus $P-pkgconf $P-protobuf $P-python $P-python-psutil \
  $P-python-glad $P-python-jinja $P-python-pip $P-python-protobuf \
  $P-qt6-base $P-qt6-declarative $P-qt6-svg $P-qt6-tools \
  $P-shaderc $P-speexdsp $P-spirv-cross $P-vulkan $P-vulkan-headers
echo "MSYS2 packages ready"
