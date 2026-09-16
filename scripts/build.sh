#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_VERSION")
SOURCE_SHA256=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_SHA256")
PYTHON_VERSION=${VERSION%.*}
PACKAGE_VERSION="$VERSION-1"

WORK_DIR=${WORK_DIR:-"$(mktemp -d "${TMPDIR:-/tmp}/python-ios-build.XXXXXX")"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}

INSTALL_PREFIX=/usr/local
FRAMEWORK_PREFIX="$INSTALL_PREFIX/Frameworks"
SOURCE_ARCHIVE="$WORK_DIR/Python-$VERSION.tar.xz"
SOURCE_DIR="$WORK_DIR/Python-$VERSION"
HOST_BUILD_DIR="$SOURCE_DIR/cross-build"
TARGET_DIR="$WORK_DIR/target"
PACKAGE_ROOT="$WORK_DIR/package-root"
DEPS_PREFIX="$HOST_BUILD_DIR/arm64-apple-ios/prefix"
BUILD_PYTHON="$HOST_BUILD_DIR/build/python.exe"

# Download and verify CPython before extracting it.
mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$TARGET_DIR" "$PACKAGE_ROOT"
printf 'Downloading CPython %s...\n' "$VERSION"
curl --fail --location --retry 3 \
    --output "$SOURCE_ARCHIVE" \
    "https://www.python.org/ftp/python/$VERSION/Python-$VERSION.tar.xz"
printf '%s  %s\n' "$SOURCE_SHA256" "$SOURCE_ARCHIVE" | shasum -a 256 -c -
tar -xJf "$SOURCE_ARCHIVE" -C "$WORK_DIR"

# Build the host interpreter and fetch the Apple dependencies.
printf 'Preparing the host Python and Apple dependencies...\n'
(
    cd "$SOURCE_DIR"
    python3 Apple/__main__.py build iOS build
    python3 Apple/__main__.py configure-host iOS arm64-apple-ios
)

# Build and stage the iOS framework.
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
        LIBS="-Wl,-needed_framework,UIKit" \
        LIBMPDEC_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBMPDEC_LIBS="-L$DEPS_PREFIX/lib -lmpdec" \
        LIBLZMA_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBLZMA_LIBS="-L$DEPS_PREFIX/lib -llzma" \
        LIBFFI_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBFFI_LIBS="-L$DEPS_PREFIX/lib -lffi" \
        LIBZSTD_CFLAGS="-I$DEPS_PREFIX/include" \
        LIBZSTD_LIBS="-L$DEPS_PREFIX/lib -lzstd"

    printf 'Building CPython with %s jobs...\n' "$JOBS"
    make -j"$JOBS"
    make install DESTDIR="$PACKAGE_ROOT" ENSUREPIP=no
)

# Install the interpreter and command wrappers.
BIN_DIR="$PACKAGE_ROOT$INSTALL_PREFIX/bin"
PYTHON_BIN="$BIN_DIR/python$PYTHON_VERSION"
PYTHON_FRAMEWORK="$PACKAGE_ROOT$FRAMEWORK_PREFIX/Python.framework"
DYNLOAD_DIR="$PACKAGE_ROOT$FRAMEWORK_PREFIX/lib/python$PYTHON_VERSION/lib-dynload"

mkdir -p "$BIN_DIR"
cp "$TARGET_DIR/python.exe" "$PYTHON_BIN"
ln -sf "python$PYTHON_VERSION" "$BIN_DIR/python3"
ln -sf "python$PYTHON_VERSION" "$BIN_DIR/python"

# Use the host interpreter: the iOS executable cannot run during the build.
set -- "$SOURCE_DIR"/Lib/ensurepip/_bundled/pip-*.whl
PYTHONPATH="$1" "$BUILD_PYTHON" -m pip install \
    --no-cache-dir \
    --no-warn-script-location \
    --prefix="$FRAMEWORK_PREFIX" \
    --root="$PACKAGE_ROOT" \
    "$1"

rm -f "$BIN_DIR/pip$PYTHON_VERSION" "$BIN_DIR/pip3" "$BIN_DIR/pip"
cp "$ROOT_DIR/packaging/pip-wrapper" "$BIN_DIR/pip"
chmod 0755 "$BIN_DIR/pip"
ln -sf pip "$BIN_DIR/pip3"
ln -sf pip "$BIN_DIR/pip$PYTHON_VERSION"

# Strip before signing so the signatures remain valid.
strip -x "$PYTHON_BIN"
strip -x "$PYTHON_FRAMEWORK/Python"
codesign --force --sign - "$PYTHON_BIN"
codesign --force --sign - --deep "$PYTHON_FRAMEWORK"
find "$DYNLOAD_DIR" -type f -name '*.so' -exec codesign --force --sign - {} \;

# Add Debian metadata directly to the staged installation.
mkdir -p "$PACKAGE_ROOT/DEBIAN"
sed "s/^Version: .*/Version: $PACKAGE_VERSION/" "$ROOT_DIR/packaging/control.in" \
    > "$PACKAGE_ROOT/DEBIAN/control"
cp "$ROOT_DIR/packaging/postinst" "$ROOT_DIR/packaging/postrm" "$PACKAGE_ROOT/DEBIAN/"
chmod 0755 "$PACKAGE_ROOT/DEBIAN/postinst" "$PACKAGE_ROOT/DEBIAN/postrm"

PACKAGE_PATH="$OUTPUT_DIR/python-ios-framework_${PACKAGE_VERSION}_iphoneos-arm.deb"
rm -f "$PACKAGE_PATH"
dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$PACKAGE_PATH"
printf 'Built: %s\n' "$PACKAGE_PATH"
