#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common-env.sh
source "$SCRIPT_DIR/common-env.sh"

source_dir="$BUILD/openssl-$OPENSSL_VER"
archive="$DEPS/openssl-$OPENSSL_VER.tar.gz"
url="https://www.openssl.org/source/openssl-$OPENSSL_VER.tar.gz"

rm -rf "$OPENSSL_ROOT" "$source_dir"
fetch_verified "$url" "$archive" "$OPENSSL_SHA256"
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
	./Configure ios64-xcrun no-shared no-tests \
		--prefix="$OPENSSL_PREFIX" \
		--openssldir=/etc/ssl \
		"-miphoneos-version-min=$MIN_IOS"
	make -j"$JOBS"
	make install_sw
)
