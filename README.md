# Python 3.12 for iOS

[![Build Status](https://github.com/k1tty-xz/python3.12-ios-arm64/actions/workflows/python3.12-ios-arm64.yml/badge.svg)](https://github.com/k1tty-xz/python3.12-ios-arm64/actions)
[![License](https://img.shields.io/github/license/k1tty-xz/python3.12-ios-arm64)](LICENSE)
[![iOS](https://img.shields.io/badge/iOS-14.5%2B-black?logo=apple)](https://apple.com)

CPython 3.12 built for **iOS arm64** and packaged as a Debian package for jailbroken devices.

## Build

The build requires macOS with Xcode and Homebrew.

Install the required tools:

```sh
bash scripts/install-build-tools.sh
```

Set the build variables:

```sh
export PY_VER=3.12.5
export LIBFFI_VER=3.4.4
export MIN_IOS=14.5
export PYTHON_FOR_BUILD="$(command -v python3.12)"
```

Build everything:

```sh
make all
```

The package is written to `work/` as:

```text
python3.12_<version>-1_iphoneos-arm.deb
```

Individual stages are also available:

```sh
make deps
make python
make package
```

## Build

The project:

1. Builds OpenSSL and libffi for iOS arm64.
2. Cross-compiles CPython using the iOS SDK.
3. Applies the required iOS cross-compilation configuration.
4. Strips and signs the resulting Mach-O binaries.
5. Packages the staged files as an `iphoneos-arm` Debian package.

The default deployment target is **iOS 14.5**.

## Package

The resulting package installs Python under `/usr/local` and adds `/usr/local/bin` to the user's `PATH`. The package provides `python3` and `python3.12`, with SSL support through OpenSSL and `ctypes` support through libffi.

## CI

A GitHub Actions workflow is provided for building the package on macOS. It uses Python 3.12 for the host build and uploads the generated `.deb` as an artifact.

## License

The build scripts and packaging are licensed under the MIT License. Python, OpenSSL, libffi, and the bundled GNU config files retain their respective licenses. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
