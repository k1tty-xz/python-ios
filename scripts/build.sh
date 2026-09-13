#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_VERSION")
SOURCE_SHA256=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_SHA256")
WORK_DIR=${WORK_DIR:-"$(mktemp -d "${TMPDIR:-/tmp}/python-ios-build.XXXXXX")"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
DEBUG_BUILD=${DEBUG_BUILD:-1}
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

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

debug() {
    [ "$DEBUG_BUILD" = 1 ] || return 0
    printf 'debug: %s\n' "$*" >&2
}

dump_config_logs() {
    [ "$DEBUG_BUILD" = 1 ] || return 0
    for log_file in \
        "$SOURCE_DIR"/config.log \
        "$SOURCE_DIR"/cross-build/*/config.log \
        "$TARGET_DIR"/config.log
    do
        [ -f "$log_file" ] || continue
        printf '\n--- %s (last 120 lines) ---\n' "$log_file" >&2
        tail -n 120 "$log_file" >&2 || true
    done
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

[ "$(uname -s)" = Darwin ] || die "this build must run on macOS"

for command_name in curl shasum make dpkg-deb xcodebuild; do
    require_command "$command_name"
done

xcodebuild -version >/dev/null
debug "uname: $(uname -a)"
debug "python3: $(command -v python3 2>&1 || true)"
debug "python3 version: $(python3 --version 2>&1 || true)"

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

printf 'Downloading CPython %s...\n' "$VERSION"
curl --fail --location --retry 3 --output "$SOURCE_ARCHIVE" "$PYTHON_URL"
printf '%s  %s\n' "$SOURCE_SHA256" "$SOURCE_ARCHIVE" | shasum -a 256 -c -

tar -xJf "$SOURCE_ARCHIVE" -C "$WORK_DIR"

printf 'Building the temporary host Python and fetching Apple dependencies...\n'
(
    cd "$SOURCE_DIR"
    if [ "$DEBUG_BUILD" = 1 ]; then set -x; fi
    if python3 Apple/__main__.py build iOS build; then
        :
    else
        status=$?
        if [ "$DEBUG_BUILD" = 1 ]; then set +x; fi
        printf 'error: building the temporary host Python failed (exit %s)\n' "$status" >&2
        dump_config_logs
        exit "$status"
    fi
    if python3 Apple/__main__.py configure-host iOS arm64-apple-ios; then
        :
    else
        status=$?
        if [ "$DEBUG_BUILD" = 1 ]; then set +x; fi
        printf 'error: configuring the iOS host Python failed (exit %s)\n' "$status" >&2
        dump_config_logs
        exit "$status"
    fi
    if [ "$DEBUG_BUILD" = 1 ]; then set +x; fi
)

BUILD_PYTHON="$SOURCE_DIR/cross-build/build/python"
if [ ! -f "$BUILD_PYTHON" ]; then
    BUILD_PYTHON="$SOURCE_DIR/cross-build/build/python.exe"
fi
debug "build Python path: $BUILD_PYTHON"
debug "build Python lookup: $(command -v "$BUILD_PYTHON" 2>&1 || true)"
if [ -e "$BUILD_PYTHON" ]; then
    if [ "$DEBUG_BUILD" = 1 ]; then
        ls -l "$BUILD_PYTHON" >&2 || true
        if command -v file >/dev/null 2>&1; then
            file "$BUILD_PYTHON" >&2 || true
        fi
        "$BUILD_PYTHON" --version >&2 || true
        "$BUILD_PYTHON" -c 'import os, sys; print("executable:", sys.executable); print("version:", sys.version); print("cwd:", os.getcwd())' >&2 || true
    fi
else
    debug "build Python does not exist"
fi
[ -f "$BUILD_PYTHON" ] || die "host Python was not built: $BUILD_PYTHON"
[ -x "$BUILD_PYTHON" ] || die "host Python is not executable: $BUILD_PYTHON"
[ -d "$DEPS_PREFIX" ] || die "Apple dependency prefix was not created: $DEPS_PREFIX"

mkdir -p "$TARGET_DIR" "$PACKAGE_ROOT" "$DEB_DIR"

export PATH="$SOURCE_DIR/Apple/iOS/Resources/bin:$DEPS_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"
printf 'Configuring CPython with Python.framework...\n'
(
    cd "$TARGET_DIR"
    debug "target configure PATH: $PATH"
    if [ "$DEBUG_BUILD" = 1 ]; then set -x; fi
    if "$SOURCE_DIR/configure" \
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
        LIBZSTD_LIBS="-L$DEPS_PREFIX/lib -lzstd"; then
        :
    else
        status=$?
        if [ "$DEBUG_BUILD" = 1 ]; then set +x; fi
        printf 'error: CPython framework configure failed (exit %s)\n' "$status" >&2
        dump_config_logs
        exit "$status"
    fi
    if [ "$DEBUG_BUILD" = 1 ]; then set +x; fi
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
[ -d "$PYTHON_FRAMEWORK" ] || die "Python.framework was not installed: $PYTHON_FRAMEWORK"
[ -f "$PYTHON_FRAMEWORK/Python" ] || die "Python.framework binary was not installed: $PYTHON_FRAMEWORK/Python"
[ -x "$TARGET_DIR/python" ] || die "target Python executable was not built: $TARGET_DIR/python"
mkdir -p "$PREFIX/bin"
cp "$TARGET_DIR/python" "$PYTHON_BIN"

# The bundled pip wheel is installed by the host interpreter so the target
# executable is never run during the cross-build.
PIP_WHEEL="$SOURCE_DIR/Lib/ensurepip/_bundled/pip-*.whl"
set -- $PIP_WHEEL
[ -f "${1:-}" ] || die "bundled pip wheel was not found"
PYTHONPATH="$1" "$BUILD_PYTHON" -m pip install \
    --no-cache-dir \
    --no-index \
    --no-warn-script-location \
    --prefix="$FRAMEWORK_PREFIX" \
    --root="$PACKAGE_ROOT" \
    pip

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
