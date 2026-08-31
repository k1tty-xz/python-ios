#!/usr/bin/env bash
# Build the standalone CPython runtime for jailbroken iOS arm64.

set -euxo pipefail

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

# This package intentionally produces a standalone jailbreak executable. Use
# CPython's supported Darwin cross-build model while forcing every compile and
# link operation to the iOS SDK.
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

cat > Modules/Setup.local <<'EOF'
*disabled*
nis
EOF

cat > config.site <<'EOF'
# Files unavailable on iOS.
ac_cv_file__dev_ptc=no
ac_cv_file__dev_ptmx=no

# APIs unavailable or unsuitable for a standalone iOS process.
ac_cv_func_system=no
ac_cv_func_pipe2=no
ac_cv_func_forkpty=no
ac_cv_func_openpty=no
ac_cv_func_sendfile=no
ac_cv_func_preadv=no
ac_cv_func_pwritev=no
ac_cv_func_getentropy=no
ac_cv_func_utimensat=no
ac_cv_func_posix_fallocate=no
ac_cv_func_clock_settime=no

# NIS is not available on iOS.
ac_cv_header_rpcsvc_yp_prot_h=no
ac_cv_header_rpcsvc_ypclnt_h=no
ac_cv_header_rpcsvc_rpcsvc_h=no
ac_cv_func_yp_get_default_domain=no
ac_cv_lib_nsl_yp_get_default_domain=no
ac_cv_have_nis=no

# Networking APIs are available in the iOS SDK.
ac_cv_func_getaddrinfo=yes
ac_cv_working_getaddrinfo=yes
ac_cv_buggy_getaddrinfo=no
ac_cv_func_getnameinfo=yes
EOF
export CONFIG_SITE="$PWD/config.site"

export CPPFLAGS="-I$DEPS/openssl-ios/usr/local/include -I$DEPS/libffi-ios/usr/local/include"
export LDFLAGS="-L$DEPS/openssl-ios/usr/local/lib -L$DEPS/libffi-ios/usr/local/lib $LDFLAGS"
export LIBS="-lssl -lcrypto"
export PKG_CONFIG_PATH="$DEPS/libffi-ios/usr/local/lib/pkgconfig:$DEPS/openssl-ios/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD="$CC"
export LDSHARED="$CC -bundle -undefined dynamic_lookup $LDFLAGS"
export LDCXXSHARED="$CXX -bundle -undefined dynamic_lookup $LDFLAGS"

./configure \
  --host="$HOST_TRIPLE" \
  --build="$BUILD_TRIPLE" \
  --prefix=/usr/local \
  --with-build-python="$PYTHON_FOR_BUILD" \
  --with-openssl="$DEPS/openssl-ios/usr/local" \
  --with-openssl-rpath=no \
  --with-ensurepip=install \
  --disable-test-modules

# Cross-compilation cannot execute the freshly built target extension modules.
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

ln -sfn "python${PY_MAJOR_MINOR}" "$STAGE/usr/local/bin/python3"

echo "Stripping target Mach-O binaries..."
while IFS= read -r -d '' file_path; do
  if file -b "$file_path" | grep -q 'Mach-O'; then
    "$STRIP" -x "$file_path"
  fi
done < <(find "$STAGE" -type f \( -name '*.dylib' -o -name '*.so' -o -path "$STAGE/usr/local/bin/*" \) -print0)

ENTITLEMENTS="$REPO_ROOT/scripts/entitlements.plist"
while IFS= read -r -d '' file_path; do
  if file -b "$file_path" | grep -q 'Mach-O'; then
    ldid -S"$ENTITLEMENTS" "$file_path"
  fi
done < <(find "$STAGE" -type f \( -name '*.dylib' -o -name '*.so' -o -path "$STAGE/usr/local/bin/*" \) -print0)
