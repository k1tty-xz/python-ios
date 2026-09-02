#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=common-env.sh
source "$SCRIPT_DIR/common-env.sh"

package="$WORKDIR/python${PY_MAJOR_MINOR}_${PACKAGE_VERSION}_iphoneos-arm.deb"
interpreter="$STAGE/usr/local/bin/python$PY_MAJOR_MINOR"
command="$STAGE/usr/local/bin/python3"
stdlib="$STAGE/usr/local/lib/python$PY_MAJOR_MINOR"

[[ -f "$package" ]] || die "package not found: $package"
[[ -x "$interpreter" ]] || die "interpreter not found: $interpreter"
[[ -L "$command" || -x "$command" ]] || die "python3 command not installed"
[[ -d "$stdlib" ]] || die "standard library not installed"
[[ -f "$stdlib/ensurepip/__main__.py" ]] || die "ensurepip not installed"
[[ ! -d "$STAGE/usr/local/lib/Python.framework" ]] || die "framework must not be packaged"

description="$(file -b "$interpreter")"
[[ "$description" == *Mach-O* ]] || die "interpreter is not Mach-O: $description"
[[ "$description" == *executable* ]] || die "interpreter is not executable: $description"
[[ "$description" == *arm64* ]] || die "interpreter is not arm64: $description"
otool -hv "$interpreter" | grep -q 'MH_EXECUTE' ||
	die "Mach-O file is not an executable"

otool -L "$interpreter" | grep -q 'Python.framework' &&
	die "interpreter links against Python.framework"

[[ "$(dpkg-deb -f "$package" Package)" == "python3.14" ]] ||
	die "unexpected package name"
[[ "$(dpkg-deb -f "$package" Version)" == "$PACKAGE_VERSION" ]] ||
	die "unexpected package version"
[[ "$(dpkg-deb -f "$package" Architecture)" == "iphoneos-arm" ]] ||
	die "unexpected Debian architecture"
grep -q '^Depends:.*ca-certificates' "$PKGROOT/DEBIAN/control" ||
	die "ca-certificates dependency is missing"

dpkg-deb -c "$package" | grep -q '/usr/local/bin/python3.14$' ||
	die "python3.14 is not in the package"
dpkg-deb -c "$package" | grep -q '/usr/local/bin/python3 -> python3.14$' ||
	die "python3 symlink is not in the package"

printf 'Validated standalone %s\n' "$package"
