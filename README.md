<img src="icon.png" width="64" alt="Python for iOS icon" />

# Python for iOS

CPython 3.14 for ARM64 jailbroken iOS devices. Includes Python.framework, the
standard library, and pip.

## Install

Download and install the package that matches your jailbreak:

| Environment | Package | Installs to |
| --- | --- | --- |
| Rootful | `_iphoneos-arm.deb` | `/usr/local` |
| Rootless (iOS 15+) | `_iphoneos-arm64.deb` | `/var/jb/usr/local` |

Run Python or pip with its full path:

```sh
# Rootful
/usr/local/bin/python3
/usr/local/bin/pip

# Rootless
/var/jb/usr/local/bin/python3
/var/jb/usr/local/bin/pip
```

Check pip with:

```sh
/usr/local/bin/python3 -m pip --version
```

> **Warning:** Add the corresponding `bin` directory to `PATH` only if you
> want this installation's `python3` and `pip` commands to be the defaults
> on your device.

## Build

Requires macOS, Xcode with the iOS SDK, Python 3, Homebrew, and `dpkg`.

```sh
brew install dpkg
./scripts/build.sh          # Build both packages
./scripts/build.sh rootful  # Build rootful only
./scripts/build.sh rootless # Build rootless only
```

Packages are written to `dist/`.

## License

Maintained by k1tty-xz. Build scripts are [MIT licensed](LICENSE); CPython and
bundled dependencies retain their own licenses. This project is independent of
Apple and the Python Software Foundation.
