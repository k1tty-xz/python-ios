#!/usr/bin/env bash
# shellcheck disable=SC2034 # sourced by the build and packaging scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

die() {
	printf 'Error: %s\n' "$*" >&2
	exit 1
}

for command in curl file mktemp otool shasum sysctl tar xcrun; do
	command -v "$command" >/dev/null 2>&1 ||
		die "required command not found: $command"
done

[[ "$(uname -s)" == "Darwin" ]] ||
	die "the build requires macOS with the full Xcode installation"

PY_VER="${PY_VER:-3.14.7}"
PY_MAJOR_MINOR="${PY_VER%.*}"
LIBFFI_VER="${LIBFFI_VER:-3.8.0}"
OPENSSL_VER="${OPENSSL_VER:-3.5.8}"
PACKAGE_REVISION="${PACKAGE_REVISION:-2}"
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

ARCH=arm64
SDK_NAME=iphoneos
IOS_SDK="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
IOS_SDK_VERSION="$(xcrun --sdk "$SDK_NAME" --show-sdk-version)"
HOST_TRIPLE="$ARCH-apple-darwin20"
BUILD_TRIPLE="$(uname -m)-apple-darwin"

SDK_CC="$(xcrun --sdk "$SDK_NAME" --find clang)"
SDK_CXX="$(xcrun --sdk "$SDK_NAME" --find clang++)"
SDK_AR="$(xcrun --sdk "$SDK_NAME" --find ar)"
SDK_RANLIB="$(xcrun --sdk "$SDK_NAME" --find ranlib)"
SDK_STRIP="$(xcrun --sdk "$SDK_NAME" --find strip)"

TARGET_CFLAGS="-arch $ARCH -isysroot $IOS_SDK -miphoneos-version-min=$MIN_IOS -fPIC"
TARGET_LDFLAGS="-arch $ARCH -isysroot $IOS_SDK -miphoneos-version-min=$MIN_IOS"
OPENSSL_ROOT="$DEPS/openssl-iphoneos"
OPENSSL_PREFIX="$OPENSSL_ROOT/usr/local"
LIBFFI_PREFIX="$DEPS/libffi-iphoneos/usr/local"
LIBFFI_CFLAGS="-I$LIBFFI_PREFIX/include"
LIBFFI_LIBS="-L$LIBFFI_PREFIX/lib -lffi"

fetch_verified() {
	local url="$1"
	local destination="$2"
	local expected_sha256="$3"
	local temporary_file
	local actual_sha256

	mkdir -p "$(dirname "$destination")"
	temporary_file="$(mktemp "$destination.tmp.XXXXXX")"

	if ! curl --fail --location --show-error --retry 5 --retry-all-errors \
		--output "$temporary_file" "$url"; then
		rm -f "$temporary_file"
		die "download failed: $url"
	fi

	if ! actual_sha256="$(shasum -a 256 "$temporary_file")"; then
		rm -f "$temporary_file"
		die "could not hash downloaded archive: $url"
	fi
	actual_sha256="${actual_sha256%% *}"

	if [[ "$actual_sha256" != "$expected_sha256" ]]; then
		rm -f "$temporary_file"
		die "SHA-256 mismatch for $url (got $actual_sha256)"
	fi

	mv "$temporary_file" "$destination" ||
		die "could not store downloaded archive: $destination"
}
