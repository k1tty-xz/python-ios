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

    work/python3.14_3.14.7-3_iphoneos-arm.deb

The build uses CPython's normal executable and static-library install, compiled
with Apple's iPhoneOS SDK. It does not build or install Python.framework.

## Scope

This is a jailbreak-only Unix-style port. Official CPython iOS support targets
embedded applications and framework distribution; this project intentionally
builds a standalone executable for a jailbroken device. It is not an App Store
distribution.

## Included

- `python3` and `python3.14`
- the Python 3.14 standard library
- OpenSSL 3.5.8 for TLS and hashlib
- libffi 3.8.0 for ctypes
- bundled mpdecimal for decimal
- pip staged from CPython's bundled wheel

Modules that depend on unavailable iOS facilities are intentionally omitted,
including curses, multiprocessing, and native subprocess support. The iOS
kernel still determines which operating-system facilities are available at
runtime. Test sockets, TLS, filesystem access, and native extension loading on
the target device before relying on a package.

## Device test

After installing the package:

    python3 --version
    python3 -c 'import sys, ssl, ctypes, sqlite3, decimal; print(sys.version); print(sys.platform)'
    python3 -m pip --version

Source builds and packages that require subprocesses are not expected to work
on iOS. Pure-Python packages and compatible prebuilt wheels are the practical
pip targets.

## Sources

- CPython 3.14.7:
  https://github.com/python/cpython/tree/v3.14.7
- CPython configure documentation:
  https://docs.python.org/3.14/using/configure.html
- PEP 730:
  https://peps.python.org/pep-0730/
