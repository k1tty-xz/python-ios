#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
root="$PWD"
work="$root/.build"
stage="$work/package"
deps="$work/deps"
jobs="$(sysctl -n hw.ncpu)"
version=3.14.7

[[ "$(uname -s)" == Darwin ]] || { echo 'Build on macOS with Xcode (GitHub Actions).'; exit 1; }
[[ ! -e "$work" ]] || { echo 'Use a clean checkout for a fresh build.'; exit 1; }
mkdir -p "$work" "$stage" "$deps" dist
while read -r sha url; do
    file="$work/${url##*/}"
    curl --fail --location --retry 3 "$url" -o "$file"
    echo "$sha  $file" | shasum -a 256 -c -
    case "$file" in *.tar.*) tar -xf "$file" -C "$work" ;; esac
done < sources.lock

source="$work/Python-$version"
mkdir "$work/host-build"
cd "$work/host-build"
"$source/configure" --prefix="$work/host" --without-ensurepip --disable-test-modules
make -j"$jobs"
make install
host_python="$work/host/bin/python3.14"

export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
export IPHONEOS_DEPLOYMENT_TARGET=14.0
export CC="$(xcrun --sdk iphoneos --find clang)"
export CXX="$(xcrun --sdk iphoneos --find clang++)"
export AR="$(xcrun --sdk iphoneos --find ar)"
export RANLIB="$(xcrun --sdk iphoneos --find ranlib)"
export CFLAGS="-O2 -fPIC -target arm64-apple-ios14.0 -isysroot $SDKROOT"
export CPPFLAGS="-I$deps/include"
export LDFLAGS="-target arm64-apple-ios14.0 -isysroot $SDKROOT -L$deps/lib"
export PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig"
unset MACOSX_DEPLOYMENT_TARGET

cd "$work/openssl-3.5.8"
./Configure ios64-xcrun no-shared no-tests no-apps --prefix="$deps" --openssldir=/usr/lib/python3.14/ssl
make -j"$jobs"
make install_sw

cd "$work/libffi-3.7.1"
./configure --host=aarch64-apple-darwin --prefix="$deps" --disable-shared --enable-static
make -j"$jobs"
make install

cd "$work/xz-5.8.3"
./configure --host=aarch64-apple-darwin --prefix="$deps" --disable-shared --enable-static --disable-nls --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-doc
make -j"$jobs"
make install

# The SQLite amalgamation needs no build generator or host executable.
cd "$work/sqlite-autoconf-3530400"
"$CC" $CFLAGS -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -c sqlite3.c -o sqlite3.o
"$AR" rcs "$deps/lib/libsqlite3.a" sqlite3.o
cp sqlite3.h sqlite3ext.h "$deps/include/"

"$host_python" "$root/patch.py" "$source"
mkdir "$work/target"
cd "$work/target"
export CPPFLAGS="$CPPFLAGS -include $root/jailbreak.h"
"$source/configure" --build="$("$source/config.guess")" --host=aarch64-apple-darwin \
    --with-build-python="$host_python" --prefix=/usr --enable-shared \
    --with-openssl="$deps" --with-openssl-rpath=no --with-pkg-config=no \
    --without-ensurepip --disable-test-modules --without-readline \
    LIBFFI_CFLAGS="-I$deps/include" LIBFFI_LIBS="$deps/lib/libffi.a" \
    LIBLZMA_CFLAGS="-I$deps/include" LIBLZMA_LIBS="$deps/lib/liblzma.a" \
    LIBSQLITE3_CFLAGS="-I$deps/include" LIBSQLITE3_LIBS="$deps/lib/libsqlite3.a" \
    py_cv_module__scproxy=n/a py_cv_module__tkinter=n/a \
    ac_cv_file__dev_ptmx=no ac_cv_file__dev_ptc=no \
    ac_cv_func_mkfifoat=no ac_cv_func_mknodat=no ac_cv_func_clock_settime=no

# Configure as POSIX Darwin, but report iOS to packaging tools so pip never
# installs macOS wheels. The compiler already detects arm64-iphoneos MULTIARCH.
"$host_python" - <<'PY'
from pathlib import Path
import re
p = Path("Makefile")
s = p.read_text()
for key, value in {"MACHDEP": "ios", "_PYTHON_HOST_PLATFORM": "ios-14.0-arm64-iphoneos",
                   "IPHONEOS_DEPLOYMENT_TARGET": "14.0"}.items():
    s, count = re.subn(rf"^{key}=.*$", f"{key}={value}", s, flags=re.M)
    assert count == 1, (key, count)
p.write_text(s)
PY
make -j"$jobs"
make install DESTDIR="$stage"

cd "$root"
mkdir -p "$stage/usr/lib/python3.14/ssl" "$stage/usr/share/doc/python3.14" "$stage/DEBIAN"
cp "$work/cacert-2026-08-13.pem" "$stage/usr/lib/python3.14/ssl/cert.pem"
cp smoke.py "$stage/usr/share/doc/python3.14/smoke.py"
cp "$source/LICENSE" "$stage/usr/share/doc/python3.14/LICENSE.cpython"
cp "$work/openssl-3.5.8/LICENSE.txt" "$stage/usr/share/doc/python3.14/LICENSE.openssl"
cp "$work/libffi-3.7.1/LICENSE" "$stage/usr/share/doc/python3.14/LICENSE.libffi"
cp "$work/xz-5.8.3/COPYING" "$stage/usr/share/doc/python3.14/LICENSE.xz"
cp sources.lock "$stage/usr/share/doc/python3.14/"

find "$stage/usr" -type f \( -name '*.dylib' -o -name '*.so' -o -name 'python3.14' \) -print0 |
while IFS= read -r -d '' file; do
    ldid -S"$root/entitlements.plist" "$file"
    file "$file"
    otool -L "$file"
done

cat > "$stage/DEBIAN/control" <<EOF
Package: python3.14
Version: $version-100
Architecture: iphoneos-arm
Maintainer: k1tty-xz <187893856+k1tty-xz@users.noreply.github.com>
Section: Development
Priority: optional
Depends: firmware (>= 14.0)
Description: CPython $version for rootful jailbroken iOS (ARM64)
 Terminal Python with pip, venv, TLS, SQLite, ctypes and subprocess support.
EOF
cat > "$stage/DEBIAN/postinst" <<'SH'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    /usr/bin/python3.14 -m ensurepip --upgrade --default-pip
fi
SH
chmod 755 "$stage/DEBIAN/postinst"
COPYFILE_DISABLE=1 dpkg-deb --root-owner-group -Zgzip --build "$stage" "dist/python3.14_${version}-100_iphoneos-arm.deb"
cp smoke.py dist/
shasum -a 256 dist/*.deb > dist/SHA256SUMS
