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
[ "$(dpkg-deb --field "$PACKAGE" Architecture)" = iphoneos-arm ]
dpkg-deb --extract "$PACKAGE" "$WORK_DIR/root"

ROOT="$WORK_DIR/root"
PREFIX="$ROOT/usr/local"
FRAMEWORK_ROOT="$PREFIX/Frameworks"
PYTHON_FRAMEWORK="$FRAMEWORK_ROOT/Python.framework"
PYTHON_BIN="$PREFIX/bin/python3.14"
DYNLOAD_DIR="$PREFIX/lib/python3.14/lib-dynload"

[ -x "$PYTHON_BIN" ]
[ -L "$PREFIX/bin/python3" ]
[ -L "$PREFIX/bin/python" ]
[ -d "$FRAMEWORK_ROOT/lib/python3.14" ]
[ -d "$DYNLOAD_DIR" ]
[ -d "$PYTHON_FRAMEWORK" ]
[ -f "$PYTHON_FRAMEWORK/Python" ]
[ -f "$PYTHON_FRAMEWORK/Info.plist" ]

command -v lipo >/dev/null 2>&1
lipo "$PYTHON_BIN" -verify_arch arm64
lipo "$PYTHON_FRAMEWORK/Python" -verify_arch arm64
codesign --verify --deep --strict "$PYTHON_BIN"
codesign --verify --deep --strict "$PYTHON_FRAMEWORK"
find "$DYNLOAD_DIR" -type f -name '*.so' -exec lipo {} -verify_arch arm64 \; -exec codesign --verify --strict {} \;
if ! otool -L "$PYTHON_BIN" | grep -E 'Python\.framework/Python' >/dev/null; then
    printf 'error: Python.framework dependency missing from executable\n' >&2
    exit 1
fi

printf 'Framework package checks passed: %s\n' "$PACKAGE"
