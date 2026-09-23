#!/bin/sh
set -eu

PACKAGE=${1:-}
[ -n "$PACKAGE" ] || {
    printf 'usage: %s path/to/package.deb\n' "$0" >&2
    exit 2
}
[ -f "$PACKAGE" ] || {
    printf 'error: package not found: %s\n' "$PACKAGE" >&2
    exit 1
}

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/python-ios-test.XXXXXX")
trap 'rm -rf "$WORK_DIR"' 0

case "$(dpkg-deb --field "$PACKAGE" Architecture)" in
    iphoneos-arm) INSTALL_PREFIX=/usr/local; PACKAGE_SHELL=/bin/sh; MIN_IOS=13.0 ;;
    iphoneos-arm64) INSTALL_PREFIX=/var/jb/usr/local; PACKAGE_SHELL=/var/jb/bin/sh; MIN_IOS=15.0 ;;
    *) printf 'error: unsupported package architecture\n' >&2; exit 1 ;;
esac
VERSION=$(dpkg-deb --field "$PACKAGE" Version)
VERSION=${VERSION%-*}
PYTHON_VERSION=${VERSION%.*}
dpkg-deb --field "$PACKAGE" Depends | grep -F "firmware (>= $MIN_IOS)" >/dev/null
dpkg-deb --extract "$PACKAGE" "$WORK_DIR/root"
dpkg-deb --control "$PACKAGE" "$WORK_DIR/control"

ROOT="$WORK_DIR/root"
PREFIX="$ROOT$INSTALL_PREFIX"
FRAMEWORK_ROOT="$PREFIX/Frameworks"
PYTHON_FRAMEWORK="$FRAMEWORK_ROOT/Python.framework"
PYTHON_BIN="$PREFIX/bin/python$PYTHON_VERSION"
DYNLOAD_DIR="$FRAMEWORK_ROOT/lib/python$PYTHON_VERSION/lib-dynload"

[ -x "$PYTHON_BIN" ]
[ "$(readlink "$PREFIX/bin/python3")" = "python$PYTHON_VERSION" ]
[ "$(readlink "$PREFIX/bin/python")" = "python$PYTHON_VERSION" ]
[ "$(readlink "$PREFIX/bin/pip3")" = pip ]
[ "$(readlink "$PREFIX/bin/pip$PYTHON_VERSION")" = pip ]
[ -d "$FRAMEWORK_ROOT/lib/python$PYTHON_VERSION/site-packages/pip" ]
[ -d "$FRAMEWORK_ROOT/lib/python$PYTHON_VERSION/test" ]
[ -f "$PYTHON_FRAMEWORK/Python" ]
[ -f "$PYTHON_FRAMEWORK/Info.plist" ]

# Templates must be fully rendered, including executable shell paths.
for script in "$PREFIX/bin/pip" "$WORK_DIR/control/postinst" "$WORK_DIR/control/postrm"; do
    [ -x "$script" ]
    [ "$(head -n 1 "$script")" = "#!$PACKAGE_SHELL" ]
    sh -n "$script"
done
grep -F "exec $INSTALL_PREFIX/bin/python$PYTHON_VERSION -m pip" "$PREFIX/bin/pip" >/dev/null
if grep -E '@[A-Z_]+@' "$WORK_DIR/control/"* "$PREFIX/bin/pip"; then
    printf 'error: unrendered packaging template\n' >&2
    exit 1
fi
if [ "$INSTALL_PREFIX" = /var/jb/usr/local ]; then
    # Only directory ancestors of /var/jb and payload beneath it are allowed.
    unexpected=$(find "$ROOT" -mindepth 1 ! -path "$ROOT/var" \
        ! -path "$ROOT/var/jb" ! -path "$ROOT/var/jb/*" -print)
    [ -z "$unexpected" ] || { printf 'error: rootless payload outside /var/jb: %s\n' "$unexpected" >&2; exit 1; }
    if grep -E '(^|[[:space:]])/usr/local' "$WORK_DIR/control/"* "$PREFIX/bin/pip"; then
        printf 'error: rootful path in rootless packaging scripts\n' >&2
        exit 1
    fi
else
    [ ! -e "$ROOT/var/jb" ]
fi

lipo "$PYTHON_BIN" -verify_arch arm64
lipo "$PYTHON_FRAMEWORK/Python" -verify_arch arm64
codesign --verify "$PYTHON_BIN"
codesign --verify "$PYTHON_FRAMEWORK"

# Check the extensions expected from the supplied iOS dependencies.
for module in _ssl _hashlib _ctypes _decimal _lzma _zstd; do
    set -- "$DYNLOAD_DIR/$module".*.so
    [ -f "$1" ] || {
        printf 'error: missing extension: %s\n' "$module" >&2
        exit 1
    }
done

find "$DYNLOAD_DIR" -type f -name '*.so' -exec sh -ec '
    for binary do
        lipo "$binary" -verify_arch arm64
        codesign --verify "$binary"
    done
' sh {} +
if ! otool -L "$PYTHON_BIN" | grep -F '@rpath/Python.framework/Python (' >/dev/null; then
    printf 'error: Python.framework dependency missing from executable\n' >&2
    exit 1
fi
if ! otool -L "$PYTHON_BIN" | grep -E 'UIKit\.framework/UIKit' >/dev/null; then
    printf 'error: UIKit dependency missing from executable; platform.system() cannot identify iOS\n' >&2
    exit 1
fi

# The framework ID and executable search path must agree with the package layout.
otool -D "$PYTHON_FRAMEWORK/Python" | grep -Fx '@rpath/Python.framework/Python'
otool -l "$PYTHON_BIN" > "$WORK_DIR/load-commands"
awk '/cmd LC_RPATH/ { rpath = 1; next }
     rpath && $1 == "path" { print $2; rpath = 0 }' "$WORK_DIR/load-commands" \
    | grep -Fx "$INSTALL_PREFIX/Frameworks"

printf 'Framework package checks passed: %s\n' "$PACKAGE"
