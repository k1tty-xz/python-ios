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
trap 'rm -rf "$WORK_DIR"' EXIT

dpkg-deb --info "$PACKAGE" >/dev/null
dpkg-deb --extract "$PACKAGE" "$WORK_DIR/root"

ROOT="$WORK_DIR/root"
PREFIX="$ROOT/usr/local"
PYTHON_BIN="$PREFIX/bin/python3.14"

[ -x "$PYTHON_BIN" ]
[ -L "$PREFIX/bin/python3" ]
[ -L "$PREFIX/bin/python" ]
[ -d "$PREFIX/lib/python3.14" ]

[ ! -e "$PREFIX/Frameworks/Python.framework" ]
[ ! -e "$PREFIX/lib/Python.framework" ]
[ ! -e "$PREFIX/lib/libpython3.14.dylib" ]

if find "$PREFIX" \( -type f -o -type l \) \( -name '*.so' -o -name '*.dylib' \) -print -quit | grep -q .; then
    printf 'error: dynamic runtime library found in package\n' >&2
    exit 1
fi
if find "$PREFIX" -type d -name 'Python.framework' -print -quit | grep -q .; then
    printf 'error: Python.framework found in package\n' >&2
    exit 1
fi

find "$PREFIX/lib" -type f -name 'libpython*.a' -print -quit | grep -q .

command -v lipo >/dev/null 2>&1
lipo -verify_arch arm64 "$PYTHON_BIN"
codesign --verify --deep --strict "$PYTHON_BIN"
if otool -L "$PYTHON_BIN" | grep -E 'Python\.framework|libpython.*\.dylib' >/dev/null; then
    printf 'error: dynamic Python library dependency found in executable\n' >&2
    exit 1
fi

printf 'Static package checks passed: %s\n' "$PACKAGE"
