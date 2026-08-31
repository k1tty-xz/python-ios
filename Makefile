# Makefile orchestrating iOS (arm64) Python build and Theos packaging
#
# Usage examples:
#   make deps            # build OpenSSL and libffi
#   make python          # build CPython and stage files (work/stage/usr)
#   make package         # copy staged files into Theos layout and package
#   make all             # deps + python + package
#
SHELL := /bin/bash

.PHONY: all deps openssl libffi python package validate clean distclean

all: deps python package

# ---- Dependencies ----

deps: openssl libffi

openssl:
	bash scripts/build-openssl.sh

libffi:
	bash scripts/build-libffi.sh

# ---- Build CPython ----

python:
	bash scripts/build-python.sh

# ---- Package (.deb) using dpkg (inline-YML equivalent) ----

package:
	bash scripts/package-dpkg.sh

# Portable checks that do not require macOS or the iOS SDK.
validate:
	@set -eu; for script in scripts/*.sh; do bash -n "$$script"; done
	@grep -q '@PACKAGE_ID@' debian/control.in

# ---- Housekeeping ----

clean:
	rm -rf work/stage work/pkgroot
	rm -f work/*.deb

distclean:
	rm -rf work
