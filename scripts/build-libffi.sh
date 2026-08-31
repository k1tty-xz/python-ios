#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

if [[ -f "$LIBFFI_PREFIX/lib/libffi.a" ]] &&
   [[ -f "$LIBFFI_PREFIX/lib/pkgconfig/libffi.pc" ]] &&
   grep -Fqx "prefix=$LIBFFI_PREFIX" "$LIBFFI_PREFIX/lib/pkgconfig/libffi.pc"; then
  echo "Info: libffi already built. Skipping..."
  exit 0
fi

rm -rf "$DEPS/libffi-ios"

cd "$DEPS"

LIBFFI_TAR="libffi-${LIBFFI_VER}.tar.gz"
LIBFFI_URL="https://github.com/libffi/libffi/releases/download/v${LIBFFI_VER}/${LIBFFI_TAR}"
fetch_verified "$LIBFFI_URL" "$DEPS/$LIBFFI_TAR" "$LIBFFI_SHA256"

tar xf "libffi-${LIBFFI_VER}.tar.gz"
cd "libffi-${LIBFFI_VER}"

./configure \
  --host="${HOST_TRIPLE}" \
  --prefix="${LIBFFI_PREFIX}" \
  --disable-shared \
  --enable-static \
  --disable-multi-os-directory

make -j"${JOBS}"

make install

cd "$DEPS"
rm -rf "libffi-${LIBFFI_VER}" "$LIBFFI_TAR"
