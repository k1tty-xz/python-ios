#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_VERSION")
SOURCE_SHA256=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_SHA256")
WORK_DIR=${WORK_DIR:-"$(mktemp -d "${TMPDIR:-/tmp}/python-ios-build.XXXXXX")"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
INSTALL_PREFIX=/usr/local
FRAMEWORK_PREFIX="$INSTALL_PREFIX/Frameworks"
SOURCE_ARCHIVE="$WORK_DIR/Python-$VERSION.tar.xz"
SOURCE_DIR="$WORK_DIR/Python-$VERSION"
TARGET_DIR="$WORK_DIR/target"
PACKAGE_ROOT="$WORK_DIR/package-root"
DEB_DIR="$WORK_DIR/deb"
DEPS_PREFIX="$SOURCE_DIR/cross-build/arm64-apple-ios/prefix"
PYTHON_URL="https://www.python.org/ftp/python/$VERSION/Python-$VERSION.tar.xz"

cleanup() {
    if [ "${KEEP_BUILD:-0}" != 1 ]; then
        rm -rf "$WORK_DIR"
    else
        printf 'Keeping build directory: %s\n' "$WORK_DIR"
    fi
}
trap cleanup EXIT

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

printf 'Downloading CPython %s...\n' "$VERSION"
curl --fail --location --retry 3 --output "$SOURCE_ARCHIVE" "$PYTHON_URL"
printf '%s  %s\n' "$SOURCE_SHA256" "$SOURCE_ARCHIVE" | shasum -a 256 -c -

tar -xJf "$SOURCE_ARCHIVE" -C "$WORK_DIR"

printf 'Building the temporary host Python and fetching Apple dependencies...\n'
(
    cd "$SOURCE_DIR"
    python3 Apple/__main__.py build iOS build
    python3 Apple/__main__.py configure-host iOS arm64-apple-ios
)

BUILD_PYTHON="$SOURCE_DIR/cross-build/build/python.exe"

mkdir -p "$TARGET_DIR" "$PACKAGE_ROOT" "$DEB_DIR"

export PATH="$SOURCE_DIR/Apple/iOS/Resources/bin:$DEPS_PREFIX/bin:$PATH"
printf 'Configuring CPython with Python.framework...\n'
(
    cd "$TARGET_DIR"
    "$SOURCE_DIR/configure" \
        --host=arm64-apple-ios \
        --build="$(uname -m)-apple-darwin" \
        --with-build-python="$BUILD_PYTHON" \
        --enable-framework="$FRAMEWORK_PREFIX" \
        --disable-test-modules \
        --with-ensurepip=no \
        --with-system-libmpdec \
        --with-openssl="$DEPS_PREFIX" \
        --with-openssl-rpath=no \
        LDFLAGS="-Wl,-rpath,$FRAMEWORK_PREFIX" \
        LIBMPDEC_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBMPDEC_LIBS="-L$DEPS_PREFIX/lib -lmpdec" \
        LIBLZMA_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBLZMA_LIBS="-L$DEPS_PREFIX/lib -llzma" \
        LIBFFI_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBFFI_LIBS="-L$DEPS_PREFIX/lib -lffi" \
        LIBZSTD_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBZSTD_LIBS="-L$DEPS_PREFIX/lib -lzstd"
)

JOBS=${JOBS:-$(sysctl -n hw.ncpu)}
printf 'Building CPython with %s jobs...\n' "$JOBS"
(
    cd "$TARGET_DIR"
    make -j"$JOBS"
    make install DESTDIR="$PACKAGE_ROOT" ENSUREPIP=no
)

PREFIX="$PACKAGE_ROOT$INSTALL_PREFIX"
PYTHON_FRAMEWORK="$PACKAGE_ROOT$FRAMEWORK_PREFIX/Python.framework"
PYTHON_BIN="$PREFIX/bin/python3.14"
TARGET_PYTHON="$TARGET_DIR/python.exe"
mkdir -p "$PREFIX/bin"
cp "$TARGET_PYTHON" "$PYTHON_BIN"

# The bundled pip wheel is installed by the host interpreter so the target
# executable is never run during the cross-build.
set -- "$SOURCE_DIR"/Lib/ensurepip/_bundled/pip-*.whl
PYTHONPATH="$1" "$BUILD_PYTHON" -m pip install \
    --no-cache-dir \
    --no-warn-script-location \
    --prefix="$FRAMEWORK_PREFIX" \
    --root="$PACKAGE_ROOT" \
    "$1"

ln -sf python3.14 "$PREFIX/bin/python3"
ln -sf python3.14 "$PREFIX/bin/python"
rm -f "$PREFIX/bin/pip3.14" "$PREFIX/bin/pip3" "$PREFIX/bin/pip"
cp "$ROOT_DIR/packaging/pip-wrapper" "$PREFIX/bin/pip"
chmod 0755 "$PREFIX/bin/pip"
ln -sf pip "$PREFIX/bin/pip3"
ln -sf pip "$PREFIX/bin/pip3.14"

strip -x "$PYTHON_BIN"
strip -x "$PYTHON_FRAMEWORK/Python"
codesign --force --sign - "$PYTHON_BIN"
codesign --force --sign - --deep "$PYTHON_FRAMEWORK"

mkdir -p "$DEB_DIR/DEBIAN"
sed "s/^Version: .*/Version: $VERSION-1/" "$ROOT_DIR/packaging/control.in" \
    > "$DEB_DIR/DEBIAN/control"
cp -R "$PACKAGE_ROOT"/. "$DEB_DIR"/

PACKAGE_PATH="$OUTPUT_DIR/python-ios-framework_${VERSION}-1_iphoneos-arm64.deb"
rm -f "$PACKAGE_PATH"
dpkg-deb --build --root-owner-group "$DEB_DIR" "$PACKAGE_PATH"

printf 'Built: %s\n' "$PACKAGE_PATH"
