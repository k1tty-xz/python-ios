# Python for jailbroken iOS (arm64)

This project builds CPython's official single-architecture iOS framework for
jailbroken arm64 devices and packages it as an installable Debian package. It
targets iOS 14.5+ and provides:

- `python3` and `python3.14` under `/usr/local/bin`;
- the `Python.framework` runtime under `/usr/local`;
- the Python standard library;
- TLS through OpenSSL 3.6.4;
- `ctypes` through libffi; and
- jailbreak-compatible signing and entitlements.

The package exposes a standalone command-line runtime while preserving the
framework layout required by CPython on iOS. It is not an XCFramework or an
App Store application bundle.

## Build requirements

Build on macOS with a full Xcode installation, not only the Command Line Tools.
Homebrew is used only for the small set of non-Apple packaging tools:

```sh
bash scripts/install-build-tools.sh
```

The default v2 toolchain is:

| Component | Version |
| --- | --- |
| CPython | 3.14.7 |
| OpenSSL | 3.6.4 |
| libffi | 3.8.0 |
| Minimum iOS | 14.5 |

All source archives are SHA-256 verified before extraction. To intentionally
build another release, override both its version and matching checksum.

## Build

The host Python must be the exact same CPython release as the target build:

```sh
export PYTHON_FOR_BUILD="$(command -v python3.14)"
make all
```

The package is written to `work/`:

```text
work/python3.14_3.14.7-4_iphoneos-arm.deb
```

Individual stages are available:

```sh
make deps       # OpenSSL and libffi
make python     # cross-compile and stage CPython
make package    # create the .deb
make clean      # remove stage and package-root output
make distclean  # remove all generated output
```

The build explicitly propagates the iOS SDK compiler, linker, archiver, and
strip tools and invokes CPython with `--enable-framework`,
`--host=arm64-apple-ios`, and `--build=arm64-apple-darwin`. No generated source
patch or network-fetched GNU config files are required.

## GitHub Actions

The manually triggered workflow builds on macOS, caches only verified native
dependencies, and uploads the resulting `.deb` artifact.

## Security and platform notes

The package is intended for jailbroken devices. Its binaries are signed with
the entitlements required by this deployment model, including disabled library
validation and no-container execution. Do not use these entitlements for a
normal sandboxed or App Store application.

Python on iOS does not provide every process-oriented Unix API. Modules such as
`os`, `subprocess`, and process signaling have platform-specific limitations;
this build disables NIS and avoids configure checks that cannot run on iOS.

## License

The build scripts and packaging are MIT-licensed. Python, OpenSSL, libffi, and
the other included materials retain their own licenses; see [NOTICE](NOTICE)
and [debian/copyright](debian/copyright).
