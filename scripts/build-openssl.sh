#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common-env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common-env.sh"

version_header="$OPENSSL_PREFIX/include/openssl/opensslv.h"
if [[ -f "$OPENSSL_PREFIX/lib/libcrypto.a" ]] &&
   grep -Fq "OPENSSL_VERSION_STR \"$OPENSSL_VER\"" "$version_header"; then
  echo "Using cached OpenSSL $OPENSSL_VER"
  exit 0
fi

rm -rf "$OPENSSL_ROOT" "$BUILD/openssl-$OPENSSL_VER"
archive="$DEPS/openssl-$OPENSSL_VER.tar.gz"
fetch_verified \
  "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/openssl-${OPENSSL_VER}.tar.gz" \
  "$archive" "$OPENSSL_SHA256"
mkdir -p "$BUILD/openssl-$OPENSSL_VER"
tar -xf "$archive" -C "$BUILD/openssl-$OPENSSL_VER" --strip-components=1
cd "$BUILD/openssl-$OPENSSL_VER"

./Configure \
  ios64-xcrun \
  no-shared \
  no-tests \
  --prefix=/usr/local \
  --openssldir=/etc/ssl \
  "-miphoneos-version-min=$MIN_IOS"
make -j"$JOBS"
make install_sw DESTDIR="$OPENSSL_ROOT"
