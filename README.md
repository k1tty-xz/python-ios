# Python for iOS

Standalone CPython for jailbroken iOS.

## Build

Build on macOS with Python 3.14.7 and Xcode command-line tools:

```sh
python3 build.py
```

GitHub Actions runs the same build automatically.

## Packages

The build produces two separate Debian packages:

- `dist/python3-ios-rootful_3.14.7_iphoneos-arm64.deb`
- `dist/python3-ios-rootless_3.14.7_iphoneos-arm64.deb`

Install the package matching the device's jailbreak layout. Python and its
standard library are installed system-wide under `/usr/local` (rootful) or
`/var/jb/usr/local` (rootless).
