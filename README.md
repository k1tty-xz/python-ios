# Python 3.14 for iOS

A standalone CPython 3.14 command-line runtime for jailbroken arm64 iOS devices.

## Build

Requirements:

- macOS with the full Xcode installation
- an iOS SDK selected by Xcode
- host Python 3.14.7

Build and validate:

    make package
    make validate

The package is written to:

    work/python3.14_3.14.7-2_iphoneos-arm.deb

The build uses CPython's normal executable and static-library install, compiled
with Apple's iPhoneOS SDK. It does not build or install Python.framework.

## Included

- `python3` and `python3.14`
- the Python 3.14 standard library
- OpenSSL 3.5.8 for TLS and hashlib
- libffi 3.8.0 for ctypes
- bundled mpdecimal for decimal
- ensurepip

The package is for jailbroken devices. It is not an App Store distribution.

## Device test

After installing the package:

    python3 --version
    python3 -c 'import sys, ssl, ctypes, sqlite3, decimal; print(sys.version); print(sys.platform)'
    python3 -m ensurepip --upgrade --default-pip

The iOS kernel still determines which operating-system facilities are available
at runtime. Test process creation, sockets, TLS, filesystem access, and native
extension loading on the target device before relying on a package.

## Sources

- CPython 3.14.7:
  https://github.com/python/cpython/tree/v3.14.7
- CPython configure documentation:
  https://docs.python.org/3.14/using/configure.html
- PEP 730:
  https://peps.python.org/pep-0730/
