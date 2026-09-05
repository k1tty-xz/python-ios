# Python for jailbroken iOS

A standalone CPython 3.14.7 interpreter for rootful ARM64 jailbreaks. The initial
deployment target is iOS 14.0. Device validation is in progress; wider jailbreak
and iOS compatibility is not yet established.

## Build

Push to `main` or a `codex/` branch, open a pull request, or run the GitHub Actions
workflow manually. Download the `python-rootful-arm64` artifact. GitHub supplies
the macOS runner and Xcode; no local Mac is required.

The workflow builds CPython and its OpenSSL, libffi, liblzma and SQLite dependencies
from pinned, SHA-256-checked upstream releases. Dependencies are linked into Python
extensions, avoiding a dependency on a particular bootstrap's library versions.
The iOS SDK provides system libraries, including zlib and bzip2.

The source adaptation enables the standalone POSIX build while reporting iOS to
packaging tools. It restores terminal output, subprocesses and user installations.
There is no emulator, launcher application, runtime monkey-patching or vendored
copy of CPython in this repository.

## Install and verify

Copy the `.deb` and `smoke.py` from the artifact to the jailbroken device, then run:

```sh
dpkg -i python3.14_3.14.7-100_iphoneos-arm.deb
python3.14 /usr/share/doc/python3.14/smoke.py
python3.14 -m venv ~/venvs/example
. ~/venvs/example/bin/activate
python -m pip install requests
```

The smoke check exercises native standard-library imports, compression, SQLite,
ctypes callbacks, child processes, threads, multiprocessing, verified HTTPS and a
real pip installation inside a temporary virtual environment.

Pure Python wheels should work. Native packages need compatible ARM64 iOS wheels
or an iOS compiler and SDK; macOS wheels are incompatible. Building arbitrary native
packages on the device is not part of this first build. Tk, desktop GUI modules,
GNU readline and rootless packaging are not included.

## Primary references

- [CPython iOS support](https://docs.python.org/3.14/using/ios.html)
- [CPython configuration](https://docs.python.org/3.14/using/configure.html)
- [CPython source and build guide](https://devguide.python.org/getting-started/setup-building/)
- [PEP 730](https://peps.python.org/pep-0730/)
- [Apple command-line build tools](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
- [GitHub runner selection](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- [GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [GitHub build artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data)
- [OpenSSL builds](https://github.com/openssl/openssl/blob/openssl-3.5/INSTALL.md)
- [libffi builds](https://github.com/libffi/libffi/blob/master/README.md)
- [XZ builds](https://tukaani.org/xz/)
- [SQLite compilation](https://sqlite.org/compile.html)
- [Mozilla CA bundle](https://curl.se/docs/caextract.html)
- [Python wheel tags](https://packaging.pypa.io/en/stable/tags.html)
- [Procursus Python recipe](https://github.com/ProcursusTeam/Procursus/blob/main/makefiles/python3.mk)
- [Theos rootless conventions](https://theos.dev/docs/rootless)
