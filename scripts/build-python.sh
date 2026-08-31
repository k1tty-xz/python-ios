#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/common-env.sh"

cd "$BUILD"

# Never mix files from a previous Python version into the new package.
rm -rf "$STAGE/usr"

if [[ -z "${PYTHON_FOR_BUILD:-}" ]]; then
  echo "Error: PYTHON_FOR_BUILD must point to a host Python ${PY_VER} executable." >&2
  exit 1
fi
if [[ ! -x "$PYTHON_FOR_BUILD" ]]; then
  echo "Error: PYTHON_FOR_BUILD='$PYTHON_FOR_BUILD' is not executable." >&2
  exit 1
fi

BUILD_PYTHON_VERSION="$("$PYTHON_FOR_BUILD" -c 'import platform; print(platform.python_version())')"
if [[ "$BUILD_PYTHON_VERSION" != "$PY_VER" ]]; then
  echo "Error: host Python must match target Python exactly." >&2
  echo "       expected: $PY_VER" >&2
  echo "       actual:   $BUILD_PYTHON_VERSION" >&2
  exit 1
fi

PYTHON_TAR="Python-${PY_VER}.tgz"
PYTHON_URL="https://www.python.org/ftp/python/${PY_VER}/${PYTHON_TAR}"
PYTHON_SOURCE="$BUILD/Python-${PY_VER}"

if [[ ! -d "$PYTHON_SOURCE" ]]; then
  fetch_verified "$PYTHON_URL" "$BUILD/$PYTHON_TAR" "$PYTHON_SHA256"
  tar xf "$PYTHON_TAR"
fi

cd "$PYTHON_SOURCE"

IOS_STUB_BIN="$PYTHON_SOURCE/Apple/iOS/Resources/bin"
if [[ ! -x "$IOS_STUB_BIN/arm64-apple-ios-clang" ]]; then
  echo "Error: CPython iOS compiler stubs are missing from the source archive." >&2
  exit 1
fi
export PATH="$IOS_STUB_BIN:$PATH"
export IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"
export CC=arm64-apple-ios-clang
export CXX=arm64-apple-ios-clang++
export CPP=arm64-apple-ios-cpp
export AR=arm64-apple-ios-ar
export RANLIB=ranlib
export STRIP=arm64-apple-ios-strip

export CPPFLAGS="-I$DEPS/openssl-ios/usr/local/include -I$DEPS/libffi-ios/usr/local/include"
export LDFLAGS="-L$DEPS/openssl-ios/usr/local/lib -L$DEPS/libffi-ios/usr/local/lib $LDFLAGS"
export LIBS="-lssl -lcrypto"
export PKG_CONFIG_PATH="$LIBFFI_PREFIX/lib/pkgconfig:$DEPS/openssl-ios/usr/local/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PKG_CONFIG_PATH"
export LD="$CC"

./configure \
  --enable-framework=/usr/local \
  --host="$HOST_TRIPLE" \
  --build="$BUILD_TRIPLE" \
  --with-build-python="$PYTHON_FOR_BUILD" \
  --with-openssl="$DEPS/openssl-ios/usr/local" \
  --with-openssl-rpath=no \
  --with-ensurepip=install \
  --disable-test-modules \
  LIBFFI_CFLAGS="$LIBFFI_CFLAGS" \
  LIBFFI_LIBS="$LIBFFI_LIBS"

# Cross-compilation cannot execute target extension modules on the build host.
if grep -q '^checksharedmods:' Makefile; then
  awk '
    /^checksharedmods:/ { print "checksharedmods:\n\t@true"; skip=1; next }
    skip && (/^[[:space:]]*$/ || /^[[:space:]]/){ next }
    { skip=0; print }
  ' Makefile > Makefile.new
  mv Makefile.new Makefile
fi

make -j"$JOBS"
make install ENSUREPIP=no DESTDIR="$STAGE"

FRAMEWORK="$STAGE/usr/local/Python.framework"
if [[ ! -x "$FRAMEWORK/Python" ]] || [[ ! -d "$STAGE/usr/local/lib" ]]; then
  echo "Error: CPython iOS framework install is incomplete." >&2
  exit 1
fi

ln -sfn "python${PY_MAJOR_MINOR}" "$STAGE/usr/local/bin/python3"

echo "Stripping target Mach-O binaries..."
while IFS= read -r -d '' file_path; do
  if file -b "$file_path" | grep -q 'Mach-O'; then
    "$STRIP" -x "$file_path"
  fi
done < <(find "$STAGE" -type f -print0)

ENTITLEMENTS="$REPO_ROOT/scripts/entitlements.plist"
while IFS= read -r -d '' file_path; do
  if file -b "$file_path" | grep -q 'Mach-O'; then
    ldid -S"$ENTITLEMENTS" "$file_path"
  fi
done < <(find "$STAGE" -type f -print0)
