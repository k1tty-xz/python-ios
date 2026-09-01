# Python 3.14 for jailbroken iOS

A native arm64 Python command-line runtime for jailbroken iOS 14.5 and later.

## Runtime

- CPython 3.14.7
- OpenSSL 3.5.8 LTS with the system CA store
- libffi 3.8.0 for `ctypes`
- pip and the Python standard library
- `subprocess` through iOS `posix_spawn`

The package installs `python3`, `python3.14`, `pip`, `pip3`, and `pip3.14` in
`/usr/local/bin`.

## Design

This is a jailbreak-specific downstream CPython target. It uses Apple Clang and
CPython's current iOS compiler wrappers, but installs a standalone shared
`libpython3.14.dylib` instead of `Python.framework`.

The executable resolves libpython through `@rpath` from `/usr/local/lib`.
Extension modules must target the same standalone runtime. Pure-Python wheels
work normally; binary wheels built for a framework-based iOS runtime are not
interchangeable.

## Build

Use macOS with the full Xcode installation:

```sh
bash scripts/install-build-tools.sh
export PYTHON_FOR_BUILD="$(command -v python3.14)"
make all
```

The result is written to:

```text
work/python3.14_3.14.7-17_iphoneos-arm.deb
```

Every source archive is SHA-256 verified. GitHub Actions also checks shell
scripts, package metadata, architecture, deployment target, Mach-O dependencies,
rpaths, entitlements, and the absence of framework or build-path leakage.

## Scope

This package is for jailbroken devices. It is not an App Store framework,
XCFramework, or application bundle. Native package builds still require an iOS
toolchain and compatible build backend; pip cannot turn desktop source archives
into iOS binaries by itself.

## License

The build and packaging code is [MIT licensed](LICENSE). Bundled components keep
their upstream licenses; see [debian/copyright](debian/copyright).

[CPython iOS documentation](https://github.com/python/cpython/blob/v3.14.7/Apple/iOS/README.md)
