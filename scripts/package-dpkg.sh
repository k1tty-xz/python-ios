#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common-env.sh
source "$SCRIPT_DIR/common-env.sh"

package="$WORKDIR/python${PY_MAJOR_MINOR}_${PACKAGE_VERSION}_iphoneos-arm.deb"

rm -rf "$PKGROOT" "$package"
mkdir -p "$PKGROOT/DEBIAN"
cp -a "$STAGE/usr" "$PKGROOT/"

interpreter="$PKGROOT/usr/local/bin/python$PY_MAJOR_MINOR"
[[ -x "$interpreter" ]] || die "standalone interpreter is missing: $interpreter"
ln -sfn "python$PY_MAJOR_MINOR" "$PKGROOT/usr/local/bin/python3"

sed "s/@VERSION@/$PACKAGE_VERSION/" \
	"$ROOT_DIR/debian/control.in" > "$PKGROOT/DEBIAN/control"
cp "$ROOT_DIR/debian/changelog" "$PKGROOT/DEBIAN/changelog"
cp "$ROOT_DIR/debian/copyright" "$PKGROOT/DEBIAN/copyright"

dpkg-deb --build --root-owner-group "$PKGROOT" "$package"
printf 'Created %s\n' "$package"
