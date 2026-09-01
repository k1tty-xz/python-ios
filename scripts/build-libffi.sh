#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common-env.sh
source "$SCRIPT_DIR/common-env.sh"

source_dir="$BUILD/libffi-$LIBFFI_VER"
archive="$DEPS/libffi-$LIBFFI_VER.tar.gz"
url="https://github.com/libffi/libffi/releases/download/v$LIBFFI_VER/libffi-$LIBFFI_VER.tar.gz"

rm -rf "$LIBFFI_PREFIX" "$source_dir"
fetch_verified "$url" "$archive" "$LIBFFI_SHA256"
mkdir -p "$BUILD"
tar -xzf "$archive" -C "$BUILD"

(
	cd "$source_dir"
	export CC="$SDK_CC"
	export CXX="$SDK_CXX"
	export AR="$SDK_AR"
	export RANLIB="$SDK_RANLIB"
	export CFLAGS="$TARGET_CFLAGS"
	export LDFLAGS="$TARGET_LDFLAGS"
	./configure \
		--host="$HOST_TRIPLE" \
		--prefix="$LIBFFI_PREFIX" \
		--disable-shared \
		--enable-static \
		--disable-multi-os-directory
	make -j"$JOBS"
	make install
)
