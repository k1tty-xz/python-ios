SHELL := /bin/bash

.PHONY: all deps openssl libffi python package clean distclean

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

clean:
	rm -rf work/build work/stage work/pkgroot work/package-verify
	rm -f work/*.deb

distclean:
	rm -rf work
