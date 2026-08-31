#!/usr/bin/env bash
# Shared, validated configuration for the iOS arm64 build.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: v2 must be built on macOS with the full Xcode installation." >&2
  exit 1
fi

for tool in curl dpkg-deb file ldid make shasum sysctl tar xcrun; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required command not found: $tool" >&2
    exit 1
  fi
done

# Versions are centralized here so the README and CI do not drift apart.
PY_VER="${PY_VER:-3.14.7}"
LIBFFI_VER="${LIBFFI_VER:-3.8.0}"
OPENSSL_VER="${OPENSSL_VER:-3.6.4}"
PACKAGE_REVISION="${PACKAGE_REVISION:-3}"
MIN_IOS="${MIN_IOS:-14.5}"
IOS_SDK_VERSION="${IOS_SDK_VERSION:-}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

# Checksums cover the default releases. If a version is overridden, its
# matching checksum must be overridden too; an unverified source is rejected.
PYTHON_SHA256="${PYTHON_SHA256:-62859805f6fdf25e2bcbf3fa3217801e1996887ca33e6a2af80674bdfa2dbe07}"
LIBFFI_SHA256="${LIBFFI_SHA256:-7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4}"
OPENSSL_SHA256="${OPENSSL_SHA256:-9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef}"

if [[ ! "$MIN_IOS" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Error: MIN_IOS must look like 14.5 (got '$MIN_IOS')." >&2
  exit 1
fi

PY_MAJOR_MINOR="${PY_VER%.*}"
PACKAGE_NAME="python${PY_MAJOR_MINOR}"
# Keep the package identifier stable so v2 upgrades the original package.
PACKAGE_ID="com.k1tty-xz.python3"
PACKAGE_VERSION="${PY_VER}-${PACKAGE_REVISION}"

WORKDIR="${WORKDIR:-$REPO_ROOT/work}"
DEPS="$WORKDIR/deps"
BUILD="$WORKDIR/build"
STAGE="$WORKDIR/stage"
PKGROOT="$WORKDIR/pkgroot"
mkdir -p "$DEPS" "$BUILD" "$STAGE"

SDK_NAME="iphoneos${IOS_SDK_VERSION}"
IOS_SDK="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
CC="$(xcrun --sdk "$SDK_NAME" -f clang)"
CXX="$(xcrun --sdk "$SDK_NAME" -f clang++)"
AR="$(xcrun --sdk "$SDK_NAME" -f ar)"
RANLIB="$(xcrun --sdk "$SDK_NAME" -f ranlib)"
STRIP="$(xcrun --sdk "$SDK_NAME" -f strip)"

# Use CPython's documented device target. The package is still a standalone
# jailbreak executable; it does not need to be an iOS app framework.
HOST_TRIPLE="arm64-apple-ios"
BUILD_TRIPLE="$(uname -m)-apple-darwin"

LIBFFI_PREFIX="$DEPS/libffi-ios/usr/local"
LIBFFI_CFLAGS="-I${LIBFFI_PREFIX}/include"
LIBFFI_LIBS="-L${LIBFFI_PREFIX}/lib -lffi"

export PY_VER LIBFFI_VER OPENSSL_VER PACKAGE_REVISION MIN_IOS IOS_SDK_VERSION
export PY_MAJOR_MINOR PACKAGE_NAME PACKAGE_ID PACKAGE_VERSION
export PYTHON_SHA256 LIBFFI_SHA256 OPENSSL_SHA256
export JOBS WORKDIR DEPS BUILD STAGE PKGROOT REPO_ROOT IOS_SDK SDK_NAME
export LIBFFI_PREFIX LIBFFI_CFLAGS LIBFFI_LIBS
export HOST_TRIPLE BUILD_TRIPLE CC CXX AR RANLIB STRIP
export CFLAGS="-target arm64-apple-ios${MIN_IOS} -arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${MIN_IOS} -fPIC"
export LDFLAGS="-target arm64-apple-ios${MIN_IOS} -arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${MIN_IOS}"

fetch_verified() {
  local url="$1"
  local file="$2"
  local expected="$3"
  local actual
  local tmp

  if [[ -f "$file" ]]; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    if [[ "$actual" == "$expected" ]]; then
      echo "Info: verified source already present: $(basename "$file")"
      return 0
    fi
    echo "Error: checksum mismatch for existing file: $file" >&2
    echo "       expected: $expected" >&2
    echo "       actual:   $actual" >&2
    return 1
  fi

  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  if ! curl --fail --location --show-error --retry 5 --retry-delay 2 --output "$tmp" "$url"; then
    rm -f "$tmp"
    return 1
  fi

  actual="$(shasum -a 256 "$tmp" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Error: checksum mismatch for downloaded file: $file" >&2
    echo "       expected: $expected" >&2
    echo "       actual:   $actual" >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$file"
}
