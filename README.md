# CPython 3.14 for jailbroken iOS

This repository builds a rootful, system-wide CPython 3.14 package for
jailbroken iOS. It currently produces one raw `.deb` artifact:

`python3.14_3.14.7-1_iphoneos-arm_rootful.deb`

This is a rootful test candidate, not a device-verified release. Rootless
packaging is intentionally deferred until the rootful package has been tested
on a jailbroken device.

## Design

- CPython is downloaded from python.org at version 3.14.7 and verified against
  its published SHA-256 checksum.
- CPython's own `Apple` build command performs the cross-build with the official
  `arm64-apple-ios` device target and an exact-version build Python.
- The installed `Python.framework`, complete installed standard library, dynamic
  extension modules, and CPython executable are placed under `/usr`.
- The executable has `/usr/lib` as an `LC_RPATH`, allowing dyld to resolve the
  framework's official `@rpath/Python.framework/Python` install name.
- Mach-O files are ad-hoc signed, then checked for the iOS platform and arm64
  architecture before the package is built.
- The workflow uploads the `.deb` directly; it does not wrap the package in a
  ZIP artifact.

CPython 3.14 officially supports one physical-device architecture: arm64. That
binary is the supported iOS device ABI for both arm64 and arm64e hardware.
CPython does not define an `arm64e-apple-ios` build target, and its official iOS
dependencies are arm64 rather than arm64e. This project therefore does not
invent a native arm64e variant or relabel duplicate binaries as separate
packages.

CPython's official iOS configuration excludes `_posixsubprocess`,
`_multiprocessing`, readline, curses, and several Unix account/system modules.
They are not patched back in here. The complete installed standard-library tree
and all extensions supported by CPython's iOS build are retained.

`pip` is not included. CPython disables `ensurepip` by default on iOS, while
`ensurepip` invokes pip through `subprocess`, which the supported iOS build does
not provide. It will only be considered after the runtime is proven on-device
and an officially supportable path can be verified.

## Build

Open **Actions → Build rootful package → Run workflow**. The job uses GitHub's
Apple-silicon `macos-15` runner and the current stable Xcode 26.3 installation.

The workflow performs build-host compilation, iOS cross-compilation, Mach-O and
package-structure checks. It cannot execute a physical-device binary on the
macOS runner, so successful CI does not prove that the command runs under a
specific jailbreak or trust-cache implementation.

## Install and test

Transfer the downloaded `.deb` to a rootful jailbroken device, then run as root:

```sh
dpkg -i ./python3.14_3.14.7-1_iphoneos-arm_rootful.deb
/usr/bin/python3.14 --version
/usr/bin/python3.14 -c 'import bz2, ctypes, decimal, lzma, sqlite3, ssl, zlib; print("ok")'
```

Report the iOS version, device model, jailbreak, command output, and any crash
log before rootless packaging is added.

## Official references

- [Python 3.14.7 release](https://www.python.org/downloads/release/python-3147/)
- [CPython 3.14 iOS build documentation](https://github.com/python/cpython/blob/v3.14.7/Apple/iOS/README.md)
- [CPython configure documentation](https://docs.python.org/3.14/using/configure.html)
- [PEP 730 — Adding iOS as a supported platform](https://peps.python.org/pep-0730/)
- [GitHub-hosted runner reference](https://docs.github.com/actions/reference/runners/github-hosted-runners)
- [GitHub artifact upload action](https://github.com/actions/upload-artifact/tree/v7.0.1)
