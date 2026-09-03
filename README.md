# CPython 3.14 for jailbroken iOS

A complete, system-wide CPython 3.14.7 package for rootful jailbroken iOS.

## Current build

- Package: `python3.14 3.14.7-8`
- Target: `arm64-apple-ios` for arm64 and arm64e devices
- Prefix: `/usr`
- Includes the standard library, subprocess support, and pip
- Rootful behavior was verified on iOS 14.8; this revision awaits a device regression test

## Install

Add `https://k1tty-xz.github.io/` to your package manager, then run:

```sh
apt update
apt install python3.14
```

Start Python with `python3` and use pip with `python3 -m pip`.

## Build

Run [Build rootful package](https://github.com/k1tty-xz/python-ios/actions/workflows/build.yml).
The workflow uses CPython's official iOS build system and official command-line
launcher, then produces one installable `.deb`.

A single patch enables jailbreak-only process support, terminal streams, pip
staging, and CLI-safe iOS version detection. These changes are not supported on
stock iOS.

Rootless packaging and the optional `readline` extension are not included yet.

## References

- [CPython iOS build documentation](https://github.com/python/cpython/blob/v3.14.7/Apple/iOS/README.md)
- [PEP 730](https://peps.python.org/pep-0730/)
