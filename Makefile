SHELL := /bin/bash

.PHONY: all deps openssl libffi python package validate clean distclean

all: deps python package

deps: openssl libffi

openssl:
	bash scripts/build-openssl.sh

libffi:
	bash scripts/build-libffi.sh

python:
	bash scripts/build-python.sh

package:
	bash scripts/package-dpkg.sh

validate:
	@set -eu; for script in scripts/*.sh; do bash -n "$$script"; done
	@grep -q '@PACKAGE_ID@' debian/control.in

clean:
	rm -rf work/stage work/pkgroot
	rm -f work/*.deb

distclean:
	rm -rf work
