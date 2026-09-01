#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common-env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common-env.sh"

python_bin="$STAGE/usr/local/bin/python$PY_MAJOR_MINOR"
[[ -x "$python_bin" ]] || {
  echo "Error: staged Python is missing; run 'make python' first." >&2
  exit 1
}

rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/DEBIAN"
cp -pR "$STAGE/usr" "$PKGROOT/"

installed_size="$(du -sk "$PKGROOT/usr" | awk '{print $1}')"
sed \
  -e "s#@PACKAGE_ID@#$PACKAGE_ID#g" \
  -e "s#@PACKAGE_VERSION@#$PACKAGE_VERSION#g" \
  -e "s#@PY_MAJOR_MINOR@#$PY_MAJOR_MINOR#g" \
  -e "s#@OPENSSL_VER@#$OPENSSL_VER#g" \
  -e "s#@MIN_IOS@#$MIN_IOS#g" \
  -e "s#@INSTALLED_SIZE@#$installed_size#g" \
  "$REPO_ROOT/debian/control.in" > "$PKGROOT/DEBIAN/control"

doc_dir="$PKGROOT/usr/share/doc/$PACKAGE_ID"
mkdir -p "$doc_dir"
gzip -9 -n -c "$REPO_ROOT/debian/changelog" > "$doc_dir/changelog.gz"
cp "$REPO_ROOT/debian/copyright" "$doc_dir/copyright"

output="$WORKDIR/${PACKAGE_NAME}_${PACKAGE_VERSION}_iphoneos-arm.deb"
dpkg-deb --build --root-owner-group "$PKGROOT" "$output"
echo "Built $output"
