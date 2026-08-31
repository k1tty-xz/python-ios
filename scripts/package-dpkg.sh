#!/usr/bin/env bash
# Build a Debian package from the staged iOS runtime.

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname -- "${BASH_SOURCE[0]}")/common-env.sh"

if [[ ! -d "$STAGE/usr" ]]; then
  echo "Error: staged runtime not found at $STAGE/usr. Run 'make python' first." >&2
  exit 1
fi

# Rebuild the package root from the stage every time. This keeps packaging
# rerunnable and prevents stale files from previous builds leaking into .deb.
rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/DEBIAN"
cp -pR "$STAGE/usr" "$PKGROOT/"

PYTHON_BIN="$PKGROOT/usr/local/bin/python${PY_MAJOR_MINOR}"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Error: packaged Python executable is missing: $PYTHON_BIN" >&2
  exit 1
fi
if [[ ! -x "$PKGROOT/usr/local/bin/python3" ]]; then
  echo "Error: python3 launcher is missing or dangling." >&2
  exit 1
fi

INSTALLED_SIZE="$(du -sk "$PKGROOT/usr" | awk '{print $1}')"
CONTROL_TEMPLATE="$REPO_ROOT/debian/control.in"
sed \
  -e "s#@PACKAGE_ID@#${PACKAGE_ID}#g" \
  -e "s#@PACKAGE_VERSION@#${PACKAGE_VERSION}#g" \
  -e "s#@PY_MAJOR_MINOR@#${PY_MAJOR_MINOR}#g" \
  -e "s#@MPDECIMAL_VER@#${MPDECIMAL_VER}#g" \
  -e "s#@OPENSSL_VER@#${OPENSSL_VER}#g" \
  -e "s#@MIN_IOS@#${MIN_IOS}#g" \
  -e "s#@INSTALLED_SIZE@#${INSTALLED_SIZE}#g" \
  "$CONTROL_TEMPLATE" > "$PKGROOT/DEBIAN/control"

DOC_DIR="$PKGROOT/usr/share/doc/$PACKAGE_ID"
mkdir -p "$DOC_DIR"
gzip -9 -n -c "$REPO_ROOT/debian/changelog" > "$DOC_DIR/changelog.gz"
cp "$REPO_ROOT/debian/copyright" "$DOC_DIR/copyright"

mkdir -p "$PKGROOT/etc/profile.d"
cat > "$PKGROOT/etc/profile.d/${PACKAGE_NAME}.sh" <<EOF
export PATH="/usr/local/bin:\$PATH"
EOF
chmod 0644 "$PKGROOT/etc/profile.d/${PACKAGE_NAME}.sh"

OUTPUT="$WORKDIR/${PACKAGE_NAME}_${PACKAGE_VERSION}_iphoneos-arm.deb"
dpkg-deb --build --root-owner-group "$PKGROOT" "$OUTPUT"
echo "Success: package built at $OUTPUT"
