# CPython for jailbroken iOS (arm64)

A native arm64 CPython build for jailbroken iOS devices, packaged as an
installable Debian package.

The project follows CPython's documented [iOS framework build][cpython-ios]
and adds a small standalone launcher for command-line use.

## Included

- CPython 3.14.7
- arm64 device binaries for iOS 14.5 and later
- `python3` and `python3.14` in `/usr/local/bin`
- `Python.framework` and the standard library
- OpenSSL 3.6.4 for TLS
- libffi 3.8.0 for `ctypes`

This package is for jailbroken devices. It is not an App Store application,
XCFramework, or general-purpose iOS app bundle.

## Requirements

Build on macOS with the full Xcode installation. The Command Line Tools alone
are not sufficient.

Install the required packaging tools with Homebrew:

```sh
bash scripts/install-build-tools.sh
```

The build verifies every downloaded source archive with SHA-256.

## Build

The host Python must match the target CPython version exactly:

```sh
export PYTHON_FOR_BUILD="$(command -v python3.14)"
make all
```

The package is written to:

```text
work/python3.14_3.14.7-13_iphoneos-arm.deb
```

Available targets:

```sh
make python     # Build and stage CPython
make package    # Build the Debian package
make clean      # Remove staged and packaged output
make distclean  # Remove all generated output
```

The build uses CPython's iOS configuration with:

- `--host=arm64-apple-ios`
- `--build=arm64-apple-darwin`
- `--enable-framework=/usr/local`

## GitHub Actions

The workflow is manually triggered from the repository's Actions tab. It builds
on macOS, validates the package architecture and launcher, and uploads the
resulting `.deb` artifact.

## Platform notes

The package uses jailbreak entitlements, including disabled library validation
and no-container execution. Do not use these entitlements for sandboxed or
App Store applications.

Some process-oriented Unix APIs have platform-specific limitations on iOS,
including parts of `os`, `subprocess`, and process signaling.

## License

The build scripts and packaging are [MIT licensed](LICENSE). Bundled components
retain their own licenses; see [debian/copyright](debian/copyright).

[cpython-ios]: https://github.com/python/cpython/blob/v3.14.7/Apple/iOS/README.md
