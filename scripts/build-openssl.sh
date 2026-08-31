#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

if [[ -f "$DEPS/openssl-ios/usr/local/lib/libcrypto.a" &&
      -f "$DEPS/openssl-ios/usr/local/lib/libssl.a" ]]; then
  echo "Info: OpenSSL already built. Skipping..."
  exit 0
fi

cd "$DEPS"

OPENSSL_TAR="openssl-${OPENSSL_VER}.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/${OPENSSL_TAR}"

if [[ ! -d "openssl-${OPENSSL_VER}" ]]; then
  fetch_verified "$OPENSSL_URL" "$DEPS/$OPENSSL_TAR" "$OPENSSL_SHA256"
  tar xf "$OPENSSL_TAR"
fi

cd "openssl-${OPENSSL_VER}"

./Configure ios64-xcrun no-tests no-shared --prefix=/usr/local
make -j"${JOBS}"
make install_sw DESTDIR="$DEPS/openssl-ios"
cd "$DEPS"
rm -rf "openssl-${OPENSSL_VER}" "${OPENSSL_TAR}"
