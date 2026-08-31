#!/usr/bin/env bash
# ==============================================================================
# Script: build-openssl.sh
# Purpose: Build the current OpenSSL release as a static iOS arm64 library.
# ==============================================================================

set -euxo pipefail

# Load common environment variables and toolchain settings
# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

# ------------------------------------------------------------------------------
# Check for Existing Build
# ------------------------------------------------------------------------------
# If the static libraries already exist, skip the build.
if [ -f "$DEPS/openssl-ios/usr/local/lib/libcrypto.a" ] && [ -f "$DEPS/openssl-ios/usr/local/lib/libssl.a" ]; then
  echo "Info: OpenSSL already built. Skipping..."
  exit 0
fi

cd "$DEPS"

# ------------------------------------------------------------------------------
# Download Source
# ------------------------------------------------------------------------------
OPENSSL_TAR="openssl-${OPENSSL_VER}.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/${OPENSSL_TAR}"

if [ ! -d "openssl-${OPENSSL_VER}" ]; then
  fetch_verified "$OPENSSL_URL" "$DEPS/$OPENSSL_TAR" "$OPENSSL_SHA256"
  tar xf "$OPENSSL_TAR"
fi

cd "openssl-${OPENSSL_VER}"

# ------------------------------------------------------------------------------
# Configure and Build
# ------------------------------------------------------------------------------
# Configure for iOS 64-bit using OpenSSL's current Xcode-aware target.
./Configure ios64-xcrun no-tests no-shared --prefix=/usr/local

# Compile
make -j"${JOBS}"

# Install software (libraries and headers) to staging directory
make install_sw DESTDIR="$DEPS/openssl-ios"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
# Remove source directory and verified tarball.
cd "$DEPS"
rm -rf "openssl-${OPENSSL_VER}" "${OPENSSL_TAR}"
