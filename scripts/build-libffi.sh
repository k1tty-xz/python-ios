#!/usr/bin/env bash
# ==============================================================================
# Script: build-libffi.sh
# Purpose: Build the current libffi release as a static iOS arm64 library.
# ==============================================================================

set -euxo pipefail

# Load common environment variables and toolchain settings
# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

# ------------------------------------------------------------------------------
# Check for Existing Build
# ------------------------------------------------------------------------------
# If the static library already exists, skip the build to save time.
if [ -f "$DEPS/libffi-ios/usr/local/lib/libffi.a" ]; then
  echo "Info: libffi already built. Skipping..."
  exit 0
fi

cd "$DEPS"

# ------------------------------------------------------------------------------
# Download Source
# ------------------------------------------------------------------------------
LIBFFI_TAR="libffi-${LIBFFI_VER}.tar.gz"
LIBFFI_URL="https://github.com/libffi/libffi/releases/download/v${LIBFFI_VER}/${LIBFFI_TAR}"
fetch_verified "$LIBFFI_URL" "$DEPS/$LIBFFI_TAR" "$LIBFFI_SHA256"

# Extract source
tar xf "libffi-${LIBFFI_VER}.tar.gz"
cd "libffi-${LIBFFI_VER}"

# ------------------------------------------------------------------------------
# Configure and Build
# ------------------------------------------------------------------------------
# Configure for iOS arm64 cross-compilation.
# CFLAGS/LDFLAGS/CC/AR/RANLIB are explicitly exported by common-env.sh.
./configure \
  --host="${HOST_TRIPLE}" \
  --prefix=/usr/local \
  --disable-shared \
  --enable-static

# Compile using the number of available CPU cores
make -j"${JOBS}"

# Install to the dependency staging directory
make install DESTDIR="$DEPS/libffi-ios"

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
# Remove source directory and tarball to free up disk space.
cd "$DEPS"
rm -rf "libffi-${LIBFFI_VER}" "$LIBFFI_TAR"
