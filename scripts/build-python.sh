#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=common-env.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common-env.sh"

: "${PYTHON_FOR_BUILD:?Set PYTHON_FOR_BUILD to Python $PY_VER on the build host}"
[[ -x "$PYTHON_FOR_BUILD" ]] || {
  echo "Error: PYTHON_FOR_BUILD is not executable: $PYTHON_FOR_BUILD" >&2
  exit 1
}
host_version="$("$PYTHON_FOR_BUILD" -c 'import platform; print(platform.python_version())')"
[[ "$host_version" == "$PY_VER" ]] || {
  echo "Error: host Python $host_version does not match target Python $PY_VER." >&2
  exit 1
}

archive="$BUILD/Python-$PY_VER.tgz"
source_dir="$BUILD/Python-$PY_VER-source"
build_dir="$BUILD/Python-$PY_VER-build"
rm -rf "$source_dir" "$build_dir" "${STAGE:?}/usr"
fetch_verified "https://www.python.org/ftp/python/${PY_VER}/Python-${PY_VER}.tgz" \
  "$archive" "$PYTHON_SHA256"
mkdir -p "$source_dir" "$build_dir"
tar -xf "$archive" -C "$source_dir" --strip-components=1
patch -d "$source_dir" -p1 < "$REPO_ROOT/debian/patches/ios-jailbreak-runtime.patch"

wrapper_dir="$source_dir/Apple/iOS/Resources/bin"
[[ -x "$wrapper_dir/arm64-apple-ios-clang" ]] || {
  echo "Error: CPython's iOS compiler wrappers are missing." >&2
  exit 1
}

pkg_config="$(command -v pkg-config)"
ldid_bin="$(command -v ldid)"
export PATH="$wrapper_dir:/usr/bin:/bin:/usr/sbin:/sbin"
export IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"
export CC=arm64-apple-ios-clang
export CXX=arm64-apple-ios-clang++
export CPP=arm64-apple-ios-cpp
export AR=arm64-apple-ios-ar
export RANLIB=ranlib
export STRIP=arm64-apple-ios-strip
export LD="$CC"
export PKG_CONFIG="$pkg_config"
export PKG_CONFIG_LIBDIR="$LIBFFI_PREFIX/lib/pkgconfig:$OPENSSL_PREFIX/lib/pkgconfig"
export CPPFLAGS="-I$OPENSSL_PREFIX/include -I$LIBFFI_PREFIX/include"
export LDFLAGS="-L$OPENSSL_PREFIX/lib -L$LIBFFI_PREFIX/lib"

cd "$build_dir"
"$source_dir/configure" \
  --prefix=/usr/local \
  --host="$HOST_TRIPLE" \
  --build="$BUILD_TRIPLE" \
  --with-build-python="$PYTHON_FOR_BUILD" \
  --enable-shared \
  --without-static-libpython \
  --with-openssl="$OPENSSL_PREFIX" \
  --with-openssl-rpath=no \
  --with-system-libmpdec=no \
  --with-libm= \
  --with-ensurepip=install \
  --disable-test-modules \
  LIBFFI_CFLAGS="$LIBFFI_CFLAGS" \
  LIBFFI_LIBS="$LIBFFI_LIBS"

"$PYTHON_FOR_BUILD" - "$build_dir/Makefile" <<'PY'
from pathlib import Path
import sys

makefile = Path(sys.argv[1])
text = makefile.read_text(encoding="utf-8")

dylib_rule = (
    "\t $(CC) -dynamiclib $(PY_CORE_LDFLAGS) -undefined dynamic_lookup "
    "-Wl,-install_name,$(prefix)/lib/libpython$(LDVERSION).dylib "
    "-Wl,-compatibility_version,$(VERSION) -Wl,-current_version,$(VERSION) "
    "-o $@ $(LIBRARY_OBJS) $(DTRACE_OBJS) $(SHLIBS) $(LIBC) $(LIBM); \\\n"
)
dylib_replacement = (
    "\tif test \"$(MACHDEP)\" = \"ios\"; then \\\n"
    "\t\t$(CC) -dynamiclib $(PY_CORE_LDFLAGS) "
    "-Wl,-install_name,@rpath/libpython$(LDVERSION).dylib "
    "-Wl,-compatibility_version,$(VERSION) -Wl,-current_version,$(VERSION) "
    "-o $@ $(LIBRARY_OBJS) $(DTRACE_OBJS) $(MODLIBS) $(SHLIBS) "
    "$(LIBC) $(LIBM); \\\n"
    "\telse \\\n"
    "\t\t$(CC) -dynamiclib $(PY_CORE_LDFLAGS) -undefined dynamic_lookup "
    "-Wl,-install_name,$(prefix)/lib/libpython$(LDVERSION).dylib "
    "-Wl,-compatibility_version,$(VERSION) -Wl,-current_version,$(VERSION) "
    "-o $@ $(LIBRARY_OBJS) $(DTRACE_OBJS) $(SHLIBS) $(LIBC) $(LIBM); \\\n"
    "\tfi\n"
)
if text.count(dylib_rule) != 1:
    raise SystemExit("unexpected libpython dylib rule count")
text = text.replace(dylib_rule, dylib_replacement, 1)

framework_header = (
    "# This rule is for iOS, which requires an annoyingly just slightly different\n"
    "# format for frameworks to macOS. It *doesn't* use a versioned framework, and\n"
    "# the Info.plist must be in the root of the framework.\n"
)
framework_guard = (
    "ifeq ($(PYTHONFRAMEWORKDIR),no-framework)\n"
    ".PHONY: no-framework no-framework/\n"
    "no-framework no-framework/:\n"
    "else\n"
)
if text.count(framework_header) != 1:
    raise SystemExit("unexpected iOS framework header count")
text = text.replace(framework_header, framework_header + framework_guard, 1)

framework_recipe = "\t$(INSTALL_DATA) $(RESSRCDIR)/Info.plist $(PYTHONFRAMEWORKDIR)/Info.plist\n"
if text.count(framework_recipe) != 1:
    raise SystemExit("unexpected iOS framework recipe count")
text = text.replace(framework_recipe, framework_recipe + "endif\n", 1)

makefile.write_text(text, encoding="utf-8")
PY
make -j"$JOBS" "libpython$PY_MAJOR_MINOR.dylib" APP_STORE_COMPLIANCE_PATCH=
make -j"$JOBS" APP_STORE_COMPLIANCE_PATCH=
make install DESTDIR="$STAGE" ENSUREPIP=no APP_STORE_COMPLIANCE_PATCH=

python_lib="$STAGE/usr/local/lib/python$PY_MAJOR_MINOR"
pip_wheel="$(find "$python_lib/ensurepip/_bundled" -name 'pip-*.whl' -type f -print -quit)"
[[ -n "$pip_wheel" ]] || {
  echo "Error: CPython's bundled pip wheel is missing." >&2
  exit 1
}
mkdir -p "$python_lib/site-packages"
unzip -q "$pip_wheel" -d "$python_lib/site-packages"

for command in pip pip3 "pip$PY_MAJOR_MINOR"; do
  install -m 0755 /dev/null "$STAGE/usr/local/bin/$command"
  printf '%s\n' \
    '#!/usr/local/bin/python3' \
    'from pip._internal.cli.main import main' \
    'raise SystemExit(main())' \
    > "$STAGE/usr/local/bin/$command"
done

python_bin="$STAGE/usr/local/bin/python$PY_MAJOR_MINOR"
libpython="$STAGE/usr/local/lib/libpython$PY_MAJOR_MINOR.dylib"
[[ -x "$python_bin" && -f "$libpython" ]] || {
  echo "Error: standalone shared CPython installation is incomplete." >&2
  exit 1
}
[[ ! -e "$STAGE/usr/local/Python.framework" ]] || {
  echo "Error: framework output is forbidden in the standalone package." >&2
  exit 1
}
ln -sfn "python$PY_MAJOR_MINOR" "$STAGE/usr/local/bin/python3"

while IFS= read -r -d '' file_path; do
  if file -b "$file_path" | grep -q Mach-O; then
    "$STRIP" -x "$file_path"
    "$ldid_bin" -S "$file_path"
  fi
done < <(find "$STAGE" -type f ! -path "$python_bin" -print0)
"$STRIP" -x "$python_bin"
"$ldid_bin" -S"$REPO_ROOT/scripts/entitlements.plist" "$python_bin"
