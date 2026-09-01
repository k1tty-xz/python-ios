#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Error: build on macOS with the full Xcode installation." >&2
  exit 1
fi

for tool in curl dpkg-deb file ldid make patch pkg-config shasum sysctl tar unzip xcrun; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Error: required command not found: $tool" >&2
    exit 1
  }
done

PY_VER="${PY_VER:-3.14.7}"
LIBFFI_VER="${LIBFFI_VER:-3.8.0}"
OPENSSL_VER="${OPENSSL_VER:-3.5.8}"
PACKAGE_REVISION="${PACKAGE_REVISION:-17}"
MIN_IOS="${MIN_IOS:-14.5}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

PYTHON_SHA256="${PYTHON_SHA256:-62859805f6fdf25e2bcbf3fa3217801e1996887ca33e6a2af80674bdfa2dbe07}"
LIBFFI_SHA256="${LIBFFI_SHA256:-7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4}"
OPENSSL_SHA256="${OPENSSL_SHA256:-a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2}"

[[ "$MIN_IOS" =~ ^[0-9]+\.[0-9]+$ ]] || {
  echo "Error: MIN_IOS must look like 14.5 (got '$MIN_IOS')." >&2
  exit 1
}

PY_MAJOR_MINOR="${PY_VER%.*}"
PACKAGE_NAME="python${PY_MAJOR_MINOR}"
PACKAGE_ID="com.k1tty-xz.python3"
PACKAGE_VERSION="${PY_VER}-${PACKAGE_REVISION}"

WORKDIR="${WORKDIR:-$REPO_ROOT/work}"
DEPS="$WORKDIR/deps"
BUILD="$WORKDIR/build"
STAGE="$WORKDIR/stage"
PKGROOT="$WORKDIR/pkgroot"
mkdir -p "$DEPS" "$BUILD" "$STAGE"

SDK_NAME=iphoneos
IOS_SDK="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
TARGET_TRIPLE="arm64-apple-ios${MIN_IOS}"
HOST_TRIPLE="$TARGET_TRIPLE"
LIBFFI_HOST="arm64-apple-ios"
BUILD_TRIPLE="$(uname -m)-apple-darwin"

SDK_CC="$(xcrun --sdk "$SDK_NAME" -f clang)"
SDK_CXX="$(xcrun --sdk "$SDK_NAME" -f clang++)"
SDK_AR="$(xcrun --sdk "$SDK_NAME" -f ar)"
SDK_RANLIB="$(xcrun --sdk "$SDK_NAME" -f ranlib)"
TARGET_CFLAGS="-target $TARGET_TRIPLE -isysroot $IOS_SDK -fPIC"
TARGET_LDFLAGS="-target $TARGET_TRIPLE -isysroot $IOS_SDK"

OPENSSL_ROOT="$DEPS/openssl-ios"
OPENSSL_PREFIX="$OPENSSL_ROOT/usr/local"
LIBFFI_PREFIX="$DEPS/libffi-ios/usr/local"
LIBFFI_CFLAGS="-I$LIBFFI_PREFIX/include"
LIBFFI_LIBS="-L$LIBFFI_PREFIX/lib -lffi"

export PY_VER LIBFFI_VER OPENSSL_VER PACKAGE_REVISION MIN_IOS JOBS
export PYTHON_SHA256 LIBFFI_SHA256 OPENSSL_SHA256 PY_MAJOR_MINOR
export PACKAGE_NAME PACKAGE_ID PACKAGE_VERSION
export WORKDIR DEPS BUILD STAGE PKGROOT REPO_ROOT
export SDK_NAME IOS_SDK TARGET_TRIPLE HOST_TRIPLE LIBFFI_HOST BUILD_TRIPLE
export SDK_CC SDK_CXX SDK_AR SDK_RANLIB TARGET_CFLAGS TARGET_LDFLAGS
export OPENSSL_ROOT OPENSSL_PREFIX LIBFFI_PREFIX LIBFFI_CFLAGS LIBFFI_LIBS

fetch_verified() {
  local url="$1" file="$2" expected="$3" actual tmp

  if [[ -f "$file" ]]; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] && return 0
    echo "Error: checksum mismatch for $file" >&2
    return 1
  fi

  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  if ! curl --fail --location --show-error --retry 5 --output "$tmp" "$url"; then
    rm -f "$tmp"
    return 1
  fi
  actual="$(shasum -a 256 "$tmp" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Error: checksum mismatch for $file" >&2
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$file"
}
