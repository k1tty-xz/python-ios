#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common-env.sh
source "$SCRIPT_DIR/common-env.sh"

: "${PYTHON_FOR_BUILD:?PYTHON_FOR_BUILD must point to a host Python 3.14.7 executable}"
[[ -x "$PYTHON_FOR_BUILD" ]] || die "host Python is not executable: $PYTHON_FOR_BUILD"
[[ "$($PYTHON_FOR_BUILD -c 'import platform; print(platform.python_version())')" == "$PY_VER" ]] ||
	die "PYTHON_FOR_BUILD must be exactly Python $PY_VER"

source_dir="$BUILD/Python-$PY_VER"
archive="$DEPS/Python-$PY_VER.tgz"
url="https://www.python.org/ftp/python/$PY_VER/Python-$PY_VER.tgz"
wrapper_dir="$source_dir/Apple/iOS/Resources/bin"

rm -rf "$source_dir" "$STAGE"
fetch_verified "$url" "$archive" "$PYTHON_SHA256"
mkdir -p "$BUILD" "$STAGE"
tar -xzf "$archive" -C "$BUILD"

[[ -x "$wrapper_dir/arm64-apple-ios-clang" ]] ||
	die "CPython iOS compiler wrappers are missing"

(
	cd "$BUILD"
	export PATH="$wrapper_dir:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"
	export IOS_SDK_VERSION
	export IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"
	export CC="arm64-apple-ios-clang"
	export CXX="arm64-apple-ios-clang++"
	export CPP="arm64-apple-ios-cpp"
	export AR="arm64-apple-ios-ar"
	export RANLIB="$SDK_RANLIB"
	export STRIP="arm64-apple-ios-strip"
	export LD="$CC"
	export PKG_CONFIG="$(command -v pkg-config)"
	export PKG_CONFIG_LIBDIR="$LIBFFI_PREFIX/lib/pkgconfig:$OPENSSL_PREFIX/lib/pkgconfig"
	export CPPFLAGS="-I$OPENSSL_PREFIX/include -I$LIBFFI_PREFIX/include"
	export LDFLAGS="-L$OPENSSL_PREFIX/lib -L$LIBFFI_PREFIX/lib"
	"$source_dir/configure" \
		--enable-framework=/usr/local/lib \
		--with-framework-name=Python \
		--host="$HOST_TRIPLE" \
		--build="$BUILD_TRIPLE" \
		--with-build-python="$PYTHON_FOR_BUILD" \
		--with-openssl="$OPENSSL_PREFIX" \
		--with-openssl-rpath=no \
		--with-system-libmpdec=no \
		--with-ensurepip=no \
		--without-static-libpython \
		LIBFFI_CFLAGS="$LIBFFI_CFLAGS" \
		LIBFFI_LIBS="$LIBFFI_LIBS"
	make -j"$JOBS"
	make install DESTDIR="$STAGE"
)

framework_binary="$(find "$STAGE/usr/local/lib/Python.framework" -type f -name Python -perm -111 -print -quit)"
[[ -n "$framework_binary" ]] || die "Python.framework executable was not installed"
[[ ! -e "$STAGE/usr/local/lib/libpython$PY_MAJOR_MINOR.a" ]] ||
	die "unexpected static libpython archive was installed"
