SHELL := /bin/bash

.PHONY: package validate clean

package:
	bash scripts/build-openssl.sh
	bash scripts/build-libffi.sh
	bash scripts/build-python.sh
	bash scripts/package-dpkg.sh

validate:
	bash scripts/validate-package.sh

clean:
	rm -rf work
