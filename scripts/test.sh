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
FRAMEWORK_ROOT="$PREFIX/Frameworks"
PYTHON_FRAMEWORK="$FRAMEWORK_ROOT/Python.framework"
PYTHON_BIN="$PREFIX/bin/python3.14"

[ -x "$PYTHON_BIN" ]
[ -L "$PREFIX/bin/python3" ]
[ -L "$PREFIX/bin/python" ]
[ -d "$FRAMEWORK_ROOT/lib/python3.14" ]
[ -d "$PYTHON_FRAMEWORK" ]
[ -f "$PYTHON_FRAMEWORK/Python" ]
[ -f "$PYTHON_FRAMEWORK/Info.plist" ]

command -v lipo >/dev/null 2>&1
lipo -verify_arch arm64 "$PYTHON_BIN"
lipo -verify_arch arm64 "$PYTHON_FRAMEWORK/Python"
codesign --verify --deep --strict "$PYTHON_BIN"
codesign --verify --deep --strict "$PYTHON_FRAMEWORK"
if ! otool -L "$PYTHON_BIN" | grep -E 'Python\.framework/Python' >/dev/null; then
    printf 'error: Python.framework dependency missing from executable\n' >&2
    exit 1
fi

printf 'Framework package checks passed: %s\n' "$PACKAGE"
