# CPython 3.14 for jailbroken iOS

[![Build](https://github.com/k1tty-xz/python-ios/actions/workflows/build.yml/badge.svg)](https://github.com/k1tty-xz/python-ios/actions/workflows/build.yml)

A system-wide CPython 3.14 build for rootful jailbroken iOS devices.

## Status

The rootful package builds on GitHub Actions for Apple's official `arm64`
iOS device target. That target is used on arm64 and arm64e devices; device
testing is still required.

Rootless support and pip support are intentionally deferred until the rootful
package has been tested.

## Install

Download the `.deb` from a successful workflow run and install it on the device:

```sh
dpkg -i ./python3.14_3.14.7-1_iphoneos-arm_rootful.deb
/usr/bin/python3.14 --version
```

Quick standard-library check:

```sh
/usr/bin/python3.14 -c 'import bz2, ctypes, lzma, sqlite3, ssl, zlib; print("ok")'
```

## Build

Run **Build rootful package** from the repository’s **Actions** tab. The
workflow downloads and verifies CPython 3.14.7, cross-compiles it with
CPython’s official iOS build, validates the output, and uploads the `.deb`
directly.

The build follows CPython’s documented iOS limitations, including unavailable
process-spawning and some platform-specific modules. It does not add custom
patches or claim device compatibility before testing.

## References

- [CPython iOS build documentation](https://github.com/python/cpython/blob/v3.14.7/Apple/iOS/README.md)
- [PEP 730](https://peps.python.org/pep-0730/)
- [GitHub Actions workflow](https://github.com/k1tty-xz/python-ios/actions/workflows/build.yml)
