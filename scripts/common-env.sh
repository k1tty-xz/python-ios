#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

die() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

for command in awk curl cut dpkg-deb file find make mktemp perl pkg-config shasum sysctl tar xcrun; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

[[ "$(uname -s)" == "Darwin" ]] || die "iOS builds require macOS with full Xcode"

PY_VER="${PY_VER:-3.14.7}"
PY_MAJOR_MINOR="$(printf '%s' "$PY_VER" | cut -d. -f1-2)"
LIBFFI_VER="${LIBFFI_VER:-3.8.0}"
OPENSSL_VER="${OPENSSL_VER:-3.5.8}"
PACKAGE_REVISION="${PACKAGE_REVISION:-1}"
MIN_IOS="${MIN_IOS:-14.5}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
PACKAGE_VERSION="$PY_VER-$PACKAGE_REVISION"

PYTHON_SHA256="${PYTHON_SHA256:-62859805f6fdf25e2bcbf3fa3217801e1996887ca33e6a2af80674bdfa2dbe07}"
LIBFFI_SHA256="${LIBFFI_SHA256:-7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4}"
OPENSSL_SHA256="${OPENSSL_SHA256:-a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2}"

WORKDIR="${WORKDIR:-$ROOT_DIR/work}"
DEPS="$WORKDIR/deps"
BUILD="$WORKDIR/build"
STAGE="$WORKDIR/stage"
PKGROOT="$WORKDIR/pkgroot"

SDK_NAME="iphoneos"
IOS_SDK="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
IOS_SDK_VERSION="$(xcrun --sdk "$SDK_NAME" --show-sdk-version)"
TARGET_TRIPLE="arm64-apple-ios$MIN_IOS"
HOST_TRIPLE="$TARGET_TRIPLE"
BUILD_TRIPLE="$(uname -m)-apple-darwin"

SDK_CC="$(xcrun --sdk "$SDK_NAME" --find clang)"
SDK_CXX="$(xcrun --sdk "$SDK_NAME" --find clang++)"
SDK_AR="$(xcrun --sdk "$SDK_NAME" --find ar)"
SDK_RANLIB="$(xcrun --sdk "$SDK_NAME" --find ranlib)"
SDK_STRIP="$(xcrun --sdk "$SDK_NAME" --find strip)"

TARGET_CFLAGS="-target $TARGET_TRIPLE -isysroot $IOS_SDK -fPIC"
TARGET_LDFLAGS="-target $TARGET_TRIPLE -isysroot $IOS_SDK"
OPENSSL_ROOT="$DEPS/openssl-ios"
OPENSSL_PREFIX="$OPENSSL_ROOT/usr/local"
LIBFFI_PREFIX="$DEPS/libffi-ios/usr/local"
LIBFFI_CFLAGS="-I$LIBFFI_PREFIX/include"
LIBFFI_LIBS="-L$LIBFFI_PREFIX/lib -lffi"

export ROOT_DIR PY_VER PY_MAJOR_MINOR LIBFFI_VER OPENSSL_VER PACKAGE_REVISION MIN_IOS JOBS
export PACKAGE_VERSION PYTHON_SHA256 LIBFFI_SHA256 OPENSSL_SHA256
export WORKDIR DEPS BUILD STAGE PKGROOT
export SDK_NAME IOS_SDK IOS_SDK_VERSION TARGET_TRIPLE HOST_TRIPLE BUILD_TRIPLE
export SDK_CC SDK_CXX SDK_AR SDK_RANLIB SDK_STRIP TARGET_CFLAGS TARGET_LDFLAGS
export OPENSSL_ROOT OPENSSL_PREFIX LIBFFI_PREFIX LIBFFI_CFLAGS LIBFFI_LIBS

fetch_verified() {
	local url="$1"
	local destination="$2"
	local expected_sha256="$3"
	local temporary_file
	local actual_sha256

	mkdir -p "$(dirname "$destination")"
	temporary_file="$(mktemp "${destination}.tmp.XXXXXX")"

	if ! curl --fail --location --show-error --retry 5 --retry-all-errors \
		--output "$temporary_file" "$url"; then
		rm -f "$temporary_file"
		die "download failed: $url"
	fi

	actual_sha256="$(shasum -a 256 "$temporary_file" | awk '{print $1}')"
	[[ "$actual_sha256" == "$expected_sha256" ]] ||
		die "SHA-256 mismatch for $url (got $actual_sha256)"

	mv "$temporary_file" "$destination" ||
		die "could not store downloaded archive: $destination"
}
