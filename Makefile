SHELL := /bin/bash

.PHONY: all deps openssl libffi mpdecimal python package clean distclean

all: deps python package

deps: openssl libffi mpdecimal

openssl:
	bash scripts/build-openssl.sh

libffi:
	bash scripts/build-libffi.sh

mpdecimal:
	bash scripts/build-mpdecimal.sh

python:
	bash scripts/build-python.sh

package:
	bash scripts/package-dpkg.sh

clean:
	rm -rf work/stage work/pkgroot
	rm -f work/*.deb

distclean:
	rm -rf work
