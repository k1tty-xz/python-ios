#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common-env.sh
source "$SCRIPT_DIR/common-env.sh"

package="$WORKDIR/python$PY_MAJOR_MINOR_${PACKAGE_VERSION}_iphoneos-arm.deb"
framework="$STAGE/usr/local/lib/Python.framework"

[[ -f "$package" ]] || die "package not found: $package"
[[ -d "$framework" ]] || die "Python.framework not found"
[[ -n "$(find "$framework" -type f -name Python -perm -111 -print -quit)" ]] ||
	die "Python.framework executable not found"
[[ ! -e "$STAGE/usr/local/lib/libpython$PY_MAJOR_MINOR.a" ]] ||
	die "static libpython archive must not be packaged"

[[ "$(dpkg-deb -f "$package" Architecture)" == "iphoneos-arm" ]] ||
	die "unexpected Debian architecture"
grep -q '^Depends:.*ca-certificates' "$PKGROOT/DEBIAN/control" ||
	die "ca-certificates dependency is missing"

while IFS= read -r -d '' binary; do
	description="$(file -b "$binary")"
	[[ "$description" == *Mach-O* ]] || die "not a Mach-O binary: $binary"
	[[ "$description" == *arm64* ]] || die "not an arm64 binary: $binary"
done < <(find "$STAGE/usr/local" -type f \( -perm -111 -o -name '*.dylib' -o -name '*.so' \) -print0)

grep -RFlq "ios-$MIN_IOS-arm64-iphoneos" "$STAGE/usr/local/lib" ||
	die "CPython iOS platform tag was not found"

printf 'Validated %s\n' "$package"
