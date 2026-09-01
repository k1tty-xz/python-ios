# Python 3.14 for iOS (arm64)

A clean, single-architecture CPython 3.14 build for physical arm64 iOS
devices, distributed as a Debian package for jailbroken systems.

## What this is

This project builds an unmodified CPython 3.14.7 iOS framework with:

- the official device ABI: arm64-apple-ios
- Apple's Xcode toolchain and CPython's iOS compiler wrappers
- Python.framework plus its separate iOS standard-library files
- OpenSSL 3.5.8 and libffi 3.8.0 built for the same device target
- bundled CPython mpdecimal, keeping the runtime self-contained

The build follows CPython's official iOS framework model. It does not patch
CPython's runtime, create a standalone non-framework interpreter, or add
unsupported process workarounds.

The result is intended for jailbroken arm64 devices and for developers who
understand the iOS framework layout. For an App Store application, embed the
framework in an Xcode project and sign it as part of that application.

## Build

Requirements:

- macOS with the full Xcode installation
- an iOS SDK selected by Xcode
- host Python 3.14.7

Run:

    make package
    make validate

The package is written to:

    work/python3.14_3.14.7-1_iphoneos-arm.deb

The workflow builds one ABI and architecture per pass. A simulator build or an
XCFramework requires a separate CPython build for that ABI.

## iOS constraints

iOS does not support normal process creation or a traditional TTY. CPython
therefore supports embedding, threads, and network sockets, while subprocess
creation and the usual interactive terminal workflow are not supported.

pip is intentionally not bundled. CPython's official iOS model does not
support the traditional runtime download, virtual-environment, and source-build
workflow. Package native extensions before embedding them, and place each iOS
dynamic module in the framework structure required by Apple and CPython.

## Sources

- CPython iOS build guide:
  https://github.com/python/cpython/blob/v3.14.7/Apple/iOS/README.md
- PEP 730, Adding iOS as a supported platform:
  https://peps.python.org/pep-0730/
- Python 3.14 configure documentation:
  https://docs.python.org/3.14/using/configure.html
- Apple framework bundles:
  https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle
