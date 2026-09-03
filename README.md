# CPython 3.14 for jailbroken iOS

[![Build](https://github.com/k1tty-xz/python-ios/actions/workflows/build.yml/badge.svg)](https://github.com/k1tty-xz/python-ios/actions/workflows/build.yml)

A system-wide CPython 3.14 for rootful jailbroken iOS devices.

## Status

The package uses CPython's official iOS build and Apple's `arm64` device target,
which runs on arm64 and arm64e devices. A small launcher uses CPython's public
configuration API so the terminal keeps normal standard input, output, and
error streams instead of redirecting them to the iOS system log. The build
also enables CPython's existing `_posixsubprocess` extension for jailbroken
iOS, where the kernel permits `fork`/`exec`.

Rootful device tests confirm normal console I/O, subprocess execution, and
pip installation. Rootless support remains deferred.

## Install

Download the `.deb` from a successful workflow run and install it on the device:

```sh
dpkg -i ./python3.14_3.14.7-7_iphoneos-arm_rootful.deb
/usr/bin/python3.14 --version
/usr/bin/python3 -m pip --version
```

Quick standard-library check:

```sh
/usr/bin/python3.14 -c 'import bz2, ctypes, lzma, sqlite3, ssl, zlib; print("OK")'
```

## Build

Run **Build rootful package** from the repository’s **Actions** tab. The
workflow downloads and verifies CPython 3.14.7, cross-compiles it with
CPython’s official iOS build, validates the output, and uploads the `.deb`
directly.

The build applies one minimal, tracked CPython source patch: it re-enables the
official `_posixsubprocess` module and `subprocess` fork/exec path for this
jailbreak-only target. This is not supported on stock iOS. Rootful device behavior has been tested.

## References

- [CPython iOS build documentation](https://github.com/python/cpython/blob/v3.14.7/Apple/iOS/README.md)
- [PEP 730](https://peps.python.org/pep-0730/)
- [GitHub Actions workflow](https://github.com/k1tty-xz/python-ios/actions/workflows/build.yml)
