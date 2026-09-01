#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common-env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common-env.sh"

if [[ -f "$LIBFFI_PREFIX/lib/libffi.a" ]] &&
   grep -Fqx "Version: $LIBFFI_VER" "$LIBFFI_PREFIX/lib/pkgconfig/libffi.pc"; then
  echo "Using cached libffi $LIBFFI_VER"
  exit 0
fi

rm -rf "$DEPS/libffi-ios" "$BUILD/libffi-$LIBFFI_VER"
archive="$DEPS/libffi-$LIBFFI_VER.tar.gz"
fetch_verified \
  "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VER}/libffi-${LIBFFI_VER}.tar.gz" \
  "$archive" "$LIBFFI_SHA256"
mkdir -p "$BUILD/libffi-$LIBFFI_VER"
tar -xf "$archive" -C "$BUILD/libffi-$LIBFFI_VER" --strip-components=1
cd "$BUILD/libffi-$LIBFFI_VER"

CC="$SDK_CC" \
CXX="$SDK_CXX" \
AR="$SDK_AR" \
RANLIB="$SDK_RANLIB" \
CFLAGS="$TARGET_CFLAGS" \
LDFLAGS="$TARGET_LDFLAGS" \
./configure \
  --host="$LIBFFI_HOST" \
  --prefix="$LIBFFI_PREFIX" \
  --disable-shared \
  --enable-static

make -j"$JOBS"
make install
