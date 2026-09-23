#!/bin/sh
set -eu

case "$*" in
    ""|all) set -- rootful rootless ;;
    rootful|rootless) ;;
    *) printf 'usage: %s [rootful|rootless|all]\n' "$0" >&2; exit 2 ;;
esac

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_VERSION")
SOURCE_SHA256=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_SHA256")
PYTHON_VERSION=${VERSION%.*}
PACKAGE_VERSION="$VERSION-2"

WORK_DIR=${WORK_DIR:-"$(mktemp -d "${TMPDIR:-/tmp}/python-ios-build.XXXXXX")"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
WORK_DIR=$(CDPATH= cd -- "$WORK_DIR" && pwd)
OUTPUT_DIR=$(CDPATH= cd -- "$OUTPUT_DIR" && pwd)

SOURCE_ARCHIVE="$WORK_DIR/Python-$VERSION.tar.xz"
SOURCE_DIR="$WORK_DIR/Python-$VERSION"
HOST_BUILD_DIR="$SOURCE_DIR/cross-build"
DEPS_PREFIX="$HOST_BUILD_DIR/arm64-apple-ios/prefix"
BUILD_PYTHON="$HOST_BUILD_DIR/build/python.exe"

# Download and verify CPython before extracting it.
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

# A subshell keeps each build's paths and configuration separate.
build_package() (
    SCHEME=$1
    case "$SCHEME" in
        rootful)
            INSTALL_PREFIX=/usr/local
            ARCHITECTURE=iphoneos-arm
            MIN_IOS=13.0
            ;;
        rootless)
            INSTALL_PREFIX=/var/jb/usr/local
            ARCHITECTURE=iphoneos-arm64
            MIN_IOS=15.0
            ;;
    esac

    FRAMEWORK_PREFIX="$INSTALL_PREFIX/Frameworks"
    BUILD_DIR=$(mktemp -d "$WORK_DIR/$SCHEME.XXXXXX")
    TARGET_DIR="$BUILD_DIR/target"
    PACKAGE_ROOT="$BUILD_DIR/package-root"
    mkdir -p "$TARGET_DIR" "$PACKAGE_ROOT"
    printf 'Building the %s package...\n' "$SCHEME"

    # Build and stage the iOS framework.
    printf 'Configuring CPython with Python.framework...\n'
    (
        cd "$TARGET_DIR"
        PATH="$SOURCE_DIR/Apple/iOS/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"
        export PATH

        "$SOURCE_DIR/configure" \
            --host=arm64-apple-ios \
            --build="$(uname -m)-apple-darwin" \
            --with-build-python="$BUILD_PYTHON" \
            --enable-framework="$FRAMEWORK_PREFIX" \
            --with-openssl="$DEPS_PREFIX" \
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
        make install DESTDIR="$PACKAGE_ROOT"
    )

    # Install the interpreter and pip module.
    BIN_DIR="$PACKAGE_ROOT$INSTALL_PREFIX/bin"
    PYTHON_BIN="$BIN_DIR/python$PYTHON_VERSION"
    PYTHON_FRAMEWORK="$PACKAGE_ROOT$FRAMEWORK_PREFIX/Python.framework"
    DYNLOAD_DIR="$PACKAGE_ROOT$FRAMEWORK_PREFIX/lib/python$PYTHON_VERSION/lib-dynload"

    mkdir -p "$BIN_DIR"
    cp "$TARGET_DIR/python.exe" "$PYTHON_BIN"
    ln -s "python$PYTHON_VERSION" "$BIN_DIR/python3"
    ln -s "python$PYTHON_VERSION" "$BIN_DIR/python"

    # Use the host interpreter: the iOS executable cannot run during the build.
    set -- "$SOURCE_DIR"/Lib/ensurepip/_bundled/pip-*.whl
    PYTHONPATH="$1" "$BUILD_PYTHON" -m pip install \
        --no-index \
        --no-deps \
        --ignore-installed \
        --prefix="$FRAMEWORK_PREFIX" \
        --root="$PACKAGE_ROOT" \
        "$1"

    # Remove pip entry points containing the temporary host interpreter's path.
    rm -f "$PACKAGE_ROOT$FRAMEWORK_PREFIX/bin/pip" \
        "$PACKAGE_ROOT$FRAMEWORK_PREFIX/bin/pip3" \
        "$PACKAGE_ROOT$FRAMEWORK_PREFIX/bin/pip$PYTHON_VERSION"

    # Strip before signing so the signatures remain valid.
    strip -x "$PYTHON_BIN"
    strip -x "$PYTHON_FRAMEWORK/Python"
    codesign --force --sign - "$PYTHON_BIN"
    codesign --force --sign - "$PYTHON_FRAMEWORK"
    find "$DYNLOAD_DIR" -type f -name '*.so' -exec sh -ec '
        for binary do codesign --force --sign - "$binary"; done
    ' sh {} +

    # Add Debian metadata directly to the staged installation.
    mkdir -p "$PACKAGE_ROOT/DEBIAN"
    sed \
        -e "s|@PYTHON_VERSION@|$PYTHON_VERSION|g" \
        -e "s|@PACKAGE_VERSION@|$PACKAGE_VERSION|g" \
        -e "s|@ARCHITECTURE@|$ARCHITECTURE|g" \
        -e "s|@SCHEME@|$SCHEME|g" \
        -e "s|@MIN_IOS@|$MIN_IOS|g" \
        "$ROOT_DIR/packaging/control.in" > "$PACKAGE_ROOT/DEBIAN/control"

    PACKAGE_PATH="$OUTPUT_DIR/python-ios-framework_${PACKAGE_VERSION}_${ARCHITECTURE}.deb"
    rm -f "$PACKAGE_PATH"
    dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$PACKAGE_PATH"
    printf 'Built: %s\n' "$PACKAGE_PATH"
)

for scheme do
    build_package "$scheme"
done
