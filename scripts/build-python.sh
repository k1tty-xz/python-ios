#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common-env.sh
source "$SCRIPT_DIR/common-env.sh"

: "${PYTHON_FOR_BUILD:?PYTHON_FOR_BUILD must point to host Python 3.14.7}"
[[ -x "$PYTHON_FOR_BUILD" ]] || die "host Python is not executable: $PYTHON_FOR_BUILD"
[[ "$("$PYTHON_FOR_BUILD" -c 'import platform; print(platform.python_version())')" == "$PY_VER" ]] ||
	die "PYTHON_FOR_BUILD must be exactly Python $PY_VER"

source_dir="$BUILD/Python-$PY_VER"
archive="$DEPS/Python-$PY_VER.tgz"
url="https://www.python.org/ftp/python/$PY_VER/Python-$PY_VER.tgz"

rm -rf "$source_dir" "$STAGE"
fetch_verified "$url" "$archive" "$PYTHON_SHA256"
mkdir -p "$BUILD" "$STAGE"
tar -xzf "$archive" -C "$BUILD"

(
	cd "$source_dir"
	patch --batch --forward -p1 < "$SCRIPT_DIR/cpython-ios.patch"
)

(
	cd "$BUILD"
	export CC="$SDK_CC"
	export CXX="$SDK_CXX"
	export AR="$SDK_AR"
	export RANLIB="$SDK_RANLIB"
	export STRIP="$SDK_STRIP"
	export LD="$SDK_CC"
	export CFLAGS="$TARGET_CFLAGS"
	export CPPFLAGS="-I$OPENSSL_PREFIX/include -I$LIBFFI_PREFIX/include"
	export LDFLAGS="$TARGET_LDFLAGS -L$OPENSSL_PREFIX/lib -L$LIBFFI_PREFIX/lib"
	export PKG_CONFIG_LIBDIR="$LIBFFI_PREFIX/lib/pkgconfig"
	export CONFIG_SITE="$SCRIPT_DIR/cpython-ios.config.site"
	export PYTHON_IOS_EXTERNAL_LIBFFI=yes
	"$source_dir/configure" \
		--prefix=/usr/local \
		--host="$HOST_TRIPLE" \
		--build="$BUILD_TRIPLE" \
		--with-build-python="$PYTHON_FOR_BUILD" \
		--with-openssl="$OPENSSL_PREFIX" \
		--with-openssl-rpath=no \
		--with-system-libmpdec=no \
		--with-ensurepip=no \
		--disable-test-modules \
		LIBFFI_CFLAGS="$LIBFFI_CFLAGS" \
		LIBFFI_LIBS="$LIBFFI_LIBS"
	make -j"$JOBS"
	make install DESTDIR="$STAGE"
	"$PYTHON_FOR_BUILD" -m ensurepip --upgrade --default-pip --root="$STAGE"
)

interpreter="$STAGE/usr/local/bin/python$PY_MAJOR_MINOR"
[[ -x "$interpreter" ]] || die "standalone interpreter was not installed: $interpreter"
[[ ! -d "$STAGE/usr/local/lib/Python.framework" ]] ||
	die "framework output was installed unexpectedly"
[[ -f "$STAGE/usr/local/lib/python$PY_MAJOR_MINOR/ensurepip/__main__.py" ]] ||
	die "ensurepip was not installed"
