#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_VERSION")
SOURCE_SHA256=$(tr -d '[:space:]' < "$ROOT_DIR/CPYTHON_SHA256")
WORK_DIR=${WORK_DIR:-"$(mktemp -d "${TMPDIR:-/tmp}/python-ios-build.XXXXXX")"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
DEBUG_BUILD=${DEBUG_BUILD:-1}
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

printf 'Adapting CPython for a rootful no-framework iOS build...\n'
python3 - "$SOURCE_DIR/configure" "$SOURCE_DIR/configure.ac" <<'PY'
from pathlib import Path
import re
import sys

guard_patterns = {
    "configure": re.compile(
        r'(?m)^([ \t]*)iOS\) as_fn_error \$\? "iOS builds must use --enable-framework" '
        r'"\$LINENO" 5 ;;\n([ \t]*)\*\)'
    ),
    "configure.ac": re.compile(
        r'(?m)^([ \t]*)iOS\) AC_MSG_ERROR\(\[iOS builds must use --enable-framework\]\) ;;\n'
        r'([ \t]*)\*\)'
    ),
}

link_pattern = re.compile(
    r'''(?m)^([ \t]*)elif test \$ac_sys_system = "iOS"; then\n'''
    r'''([ \t]*)LINKFORSHARED="-Wl,-stack_size,\$stack_size \$LINKFORSHARED "'\$\(PYTHONFRAMEWORKDIR\)/\$\(PYTHONFRAMEWORK\)'\n'''
    r'''([ \t]*)fi'''
)
link_replacement = (
    r'\1elif test $ac_sys_system = "iOS"; then\n'
    r'\2LINKFORSHARED="-Wl,-stack_size,$stack_size $LINKFORSHARED"\n'
    r'\2if test "$enable_framework"; then\n'
    r'''\2    LINKFORSHARED="$LINKFORSHARED "'$(PYTHONFRAMEWORKDIR)/$(PYTHONFRAMEWORK)'\n'''
    r'\2fi\n'
    r'\3fi'
)

for name in sys.argv[1:]:
    path = Path(name)
    text = path.read_text(encoding="utf-8")

    guard = guard_patterns[path.name]
    text, count = guard.subn(r'\1iOS|*)', text)
    if count != 2:
        raise SystemExit(f"expected two iOS framework guards in {path}, found {count}")

    text, count = link_pattern.subn(link_replacement, text)
    if count != 1:
        raise SystemExit(f"expected one iOS link rule in {path}, found {count}")

    path.write_text(text, encoding="utf-8")
PY

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

printf 'Configuring static CPython...\n'
(
    cd "$TARGET_DIR"
    export PATH="$SOURCE_DIR/Apple/iOS/Resources/bin:$DEPS_PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"
    debug "target configure PATH: $PATH"
    if [ "$DEBUG_BUILD" = 1 ]; then set -x; fi
    if "$SOURCE_DIR/configure" \
        --prefix=/usr/local \
        --host=arm64-apple-ios \
        --build="$(uname -m)-apple-darwin" \
        --with-build-python="$BUILD_PYTHON" \
        --disable-framework \
        --disable-test-modules \
        --with-ensurepip=no \
        --with-system-libmpdec \
        --with-openssl="$DEPS_PREFIX" \
        --with-openssl-rpath=no \
        MODULE_BUILDTYPE=static \
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
        printf 'error: static CPython configure failed (exit %s)\n' "$status" >&2
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

PREFIX="$PACKAGE_ROOT/usr/local"
PYTHON_BIN="$PREFIX/bin/python3.14"
[ -x "$PYTHON_BIN" ] || die "static Python executable was not installed: $PYTHON_BIN"

# The bundled pip wheel is installed by the host interpreter so the target
# executable is never run during the cross-build.
PIP_WHEEL="$SOURCE_DIR/Lib/ensurepip/_bundled/pip-*.whl"
set -- $PIP_WHEEL
[ -f "${1:-}" ] || die "bundled pip wheel was not found"
PYTHONPATH="$1" "$BUILD_PYTHON" -m pip install \
    --no-cache-dir \
    --no-index \
    --no-warn-script-location \
    --prefix=/usr/local \
    --root="$PACKAGE_ROOT" \
    pip

ln -sf python3.14 "$PREFIX/bin/python3"
ln -sf python3.14 "$PREFIX/bin/python"
rm -f "$PREFIX/bin/pip3.14" "$PREFIX/bin/pip3" "$PREFIX/bin/pip"
cp "$ROOT_DIR/packaging/pip-wrapper" "$PREFIX/bin/pip"
chmod 0755 "$PREFIX/bin/pip"
ln -sf pip "$PREFIX/bin/pip3"
ln -sf pip "$PREFIX/bin/pip3.14"

if find "$PREFIX" \( -type f -o -type l \) \( -name '*.so' -o -name '*.dylib' \) -print -quit | grep -q .; then
    die "static package unexpectedly contains a dynamic runtime library"
fi
if find "$PREFIX" -type d -name 'Python.framework' -print -quit | grep -q .; then
    die "static package unexpectedly contains Python.framework"
fi

strip -x "$PYTHON_BIN"
codesign --force --sign - "$PYTHON_BIN"

mkdir -p "$DEB_DIR/DEBIAN"
sed "s/^Version: .*/Version: $VERSION-1/" "$ROOT_DIR/packaging/control.in" \
    > "$DEB_DIR/DEBIAN/control"
cp -R "$PACKAGE_ROOT"/. "$DEB_DIR"/

PACKAGE_PATH="$OUTPUT_DIR/python-ios-static_${VERSION}-1_iphoneos-arm64.deb"
rm -f "$PACKAGE_PATH"
dpkg-deb --build --root-owner-group "$DEB_DIR" "$PACKAGE_PATH"

printf 'Built: %s\n' "$PACKAGE_PATH"
