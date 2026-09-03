#!/usr/bin/env python3
"""Build CPython Debian packages for iOS."""

from __future__ import annotations

import argparse
import gzip
import io
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from collections.abc import Mapping, Sequence
from pathlib import Path


PYTHON_VERSION = "3.14.7"
PACKAGE_VERSION = "3.14.7-2"
CPYTHON_SHA = "823f0323ee6ec1402088b73bce1a38473cac36dc"
IOS_HOST = "arm64-apple-ios"
DEPS = (
    "BZip2-1.0.8-2",
    "libFFI-3.4.7-2",
    "OpenSSL-3.5.7-1",
    "XZ-5.6.4-2",
    "mpdecimal-4.0.0-2",
    "zstd-1.5.7-1",
)
DEPS_URL = "https://github.com/beeware/cpython-apple-source-deps/releases/download"


def run(
    command: Sequence[str | Path],
    *,
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
) -> None:
    print("+", " ".join(map(str, command)))
    subprocess.run(command, cwd=cwd, env=env, check=True)


def get(command: Sequence[str | Path]) -> str:
    return subprocess.check_output(command, text=True).strip()


def replace(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise RuntimeError(f"unexpected {path}: {old!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def patch(source):
    configure = source / "configure"
    replace(
        source / "Python/initconfig.c",
        "#define USE_SYSTEM_LOGGER_DEFAULT 1;\n",
        "#define USE_SYSTEM_LOGGER_DEFAULT 0;\n",
    )
    replace(
        source / "Lib/_ios_support.py",
        "import sys\n",
        "import os\nimport sys\n",
    )
    replace(
        source / "Lib/_ios_support.py",
        """    system = objc.objc_msgSend(device_systemName, SEL_UTF8String).decode()
    release = objc.objc_msgSend(device_systemVersion, SEL_UTF8String).decode()
    model = objc.objc_msgSend(device_model, SEL_UTF8String).decode()
""",
        """    values = tuple(
        objc.objc_msgSend(value, SEL_UTF8String)
        for value in (device_systemName, device_systemVersion, device_model)
    )
    if any(value is None for value in values):
        release = os.popen(
            "sysctl -n kern.osproductversion 2>/dev/null"
        ).read().strip() or "13.0"
        return ("iOS", release, "", is_simulator)
    return tuple(value.decode() for value in values) + (is_simulator,)
""",
    )
    replace(
        configure,
        '\t\t\tiOS) as_fn_error $? "iOS builds must use --enable-framework" "$LINENO" 5 ;;\n',
        "",
    )
    replace(
        configure,
        '\t\tiOS) as_fn_error $? "iOS builds must use --enable-framework" "$LINENO" 5 ;;\n',
        "",
    )
    replace(
        configure,
        "\tiOS/*)\n\t\tLDSHARED='$(CC) -dynamiclib -F . -framework $(PYTHONFRAMEWORK)'\n\t\tLDCXXSHARED='$(CXX) -dynamiclib -F . -framework $(PYTHONFRAMEWORK)'\n\t\tBLDSHARED=\"$LDSHARED\"\n",
        "\tiOS/*)\n\t\tLDSHARED='$(CC) -bundle -undefined dynamic_lookup'\n\t\tLDCXXSHARED='$(CXX) -bundle -undefined dynamic_lookup'\n\t\tBLDSHARED=\"$LDSHARED\"\n",
    )
    replace(
        configure,
        '\tDarwin/*|iOS/*)\n\t\tLINKFORSHARED="$extra_undefs -framework CoreFoundation"\n',
        '\tDarwin/*)\n\t\tLINKFORSHARED="$extra_undefs -framework CoreFoundation"\n',
    )
    replace(
        configure,
        'if test "$ac_sys_system" = "iOS"; then\n  MODULE_DEPS_SHARED="$MODULE_DEPS_SHARED \\$(PYTHONFRAMEWORKDIR)/\\$(PYTHONFRAMEWORK)"\nfi\n',
        'if test "$ac_sys_system" = "iOS" && test "$enable_framework"; then\n  MODULE_DEPS_SHARED="$MODULE_DEPS_SHARED \\$(PYTHONFRAMEWORKDIR)/\\$(PYTHONFRAMEWORK)"\nfi\n',
    )
    replace(
        configure,
        '      iOS)\n        # Always apply the compliance patch on iOS; we can use the macOS patch\n        APP_STORE_COMPLIANCE_PATCH="Mac/Resources/app-store-compliance.patch"\n        { printf "%s\\n" "$as_me:${as_lineno-$LINENO}: result: applying default app store compliance patch" >&5\nprintf "%s\\n" "applying default app store compliance patch" >&6; }\n        ;;\n',
        '      iOS)\n        APP_STORE_COMPLIANCE_PATCH=\n        { printf "%s\\n" "$as_me:${as_lineno-$LINENO}: result: not patching for app store compliance" >&5\nprintf "%s\\n" "not patching for app store compliance" >&6; }\n        ;;\n',
    )
    replace(
        configure,
        "  iOS) :\n\n\n\n    py_cv_module__curses=n/a\n    py_cv_module__curses_panel=n/a\n    py_cv_module__gdbm=n/a\n    py_cv_module__multiprocessing=n/a\n    py_cv_module__posixshmem=n/a\n    py_cv_module__posixsubprocess=n/a\n    py_cv_module__scproxy=n/a\n    py_cv_module__tkinter=n/a\n    py_cv_module_grp=n/a\n    py_cv_module_nis=n/a\n    py_cv_module_readline=n/a\n    py_cv_module_pwd=n/a\n    py_cv_module_spwd=n/a\n    py_cv_module_syslog=n/a\n    py_cv_module_=n/a\n\n   ;; #(\n  CYGWIN*) :",
        "  iOS) :\n\n    py_cv_module__curses=n/a\n    py_cv_module__curses_panel=n/a\n    py_cv_module__scproxy=n/a\n\n   ;; #(\n  CYGWIN*) :",
    )
    replace(
        source / "Lib/subprocess.py",
        'sys.platform not in {"emscripten", "wasi", "ios", "tvos", "watchos"}',
        'sys.platform not in {"emscripten", "wasi", "tvos", "watchos"}',
    )
    replace(
        source / "Lib/site.py",
        "Emscripten, iOS, tvOS, VxWorks, WASI, and watchOS",
        "Emscripten, tvOS, VxWorks, WASI, and watchOS",
    )
    replace(
        source / "Lib/site.py",
        '{"emscripten", "ios", "tvos", "vxworks", "wasi", "watchos"}',
        '{"emscripten", "tvos", "vxworks", "wasi", "watchos"}',
    )
    replace(
        source / "Lib/sysconfig/__init__.py",
        "Emscripten, iOS, tvOS, VxWorks, WASI, and watchOS",
        "Emscripten, tvOS, VxWorks, WASI, and watchOS",
    )
    replace(
        source / "Lib/sysconfig/__init__.py",
        '{"emscripten", "ios", "tvos", "vxworks", "wasi", "watchos"}',
        '{"emscripten", "tvos", "vxworks", "wasi", "watchos"}',
    )


def download(url: str, destination: Path) -> None:
    temporary = destination.with_name(f".{destination.name}.tmp")
    try:
        with urllib.request.urlopen(
            url, timeout=120
        ) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def dependencies(prefix: Path, cache: Path) -> None:
    prefix.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    for dep in DEPS:
        name = f"{dep.lower()}-iphoneos.arm64.tar.gz"
        archive = cache / name
        if not archive.exists():
            download(f"{DEPS_URL}/{dep}/{name}", archive)
        shutil.unpack_archive(archive, prefix)
    for dylib in prefix.rglob("*.dylib"):
        dylib.unlink()


def host_python() -> Path:
    if sys.version_info[:3] != tuple(map(int, PYTHON_VERSION.split("."))):
        raise RuntimeError(f"the build requires Python {PYTHON_VERSION}")
    return Path(sys.executable).resolve()


def ios_env(source: Path, min_ios: str, epoch: int) -> dict[str, str]:
    environment = dict(os.environ)
    for name in (
        "PKG_CONFIG_PATH",
        "Python_ROOT_DIR",
        "Python2_ROOT_DIR",
        "Python3_ROOT_DIR",
    ):
        environment.pop(name, None)
    environment.update(
        {
            "PATH": (
                f"{source / 'Apple/iOS/Resources/bin'}:"
                "/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin"
            ),
            "CPPFLAGS": "-D_DARWIN_C_SOURCE",
            "IPHONEOS_DEPLOYMENT_TARGET": min_ios,
            "SOURCE_DATE_EPOCH": str(epoch),
        }
    )
    return environment


def tar_gz(root: Path, epoch: int) -> bytes:
    stream = io.BytesIO()
    with gzip.GzipFile(
        fileobj=stream, mode="wb", mtime=epoch
    ) as zipped, tarfile.open(fileobj=zipped, mode="w:", format=tarfile.GNU_FORMAT) as tar:
        for path in sorted(root.rglob("*")):
            info = tar.gettarinfo(path, arcname=str(path.relative_to(root)))
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mtime = epoch
            if info.isreg():
                with path.open("rb") as file:
                    tar.addfile(info, file)
            else:
                tar.addfile(info)
    return stream.getvalue()


def member(name: str, data: bytes, epoch: int) -> bytes:
    header = (
        f"{name}/".ljust(16)
        + f"{epoch}".ljust(12)
        + "0".ljust(6)
        + "0".ljust(6)
        + "100644".ljust(8)
        + f"{len(data)}".ljust(10)
        + "`\n"
    ).encode()
    return header + data + (b"\n" if len(data) % 2 else b"")


def sign(stage: Path) -> None:
    binaries = [next(stage.glob("**/bin/python3.14"))]
    binaries.extend(path for path in stage.rglob("*.so") if path.is_file())
    for binary in binaries:
        run(
            [
                "codesign",
                "--force",
                "--sign",
                "-",
                "--timestamp=none",
                binary,
            ]
        )
        run(["codesign", "--verify", "--strict", binary])


def install_pip(stage: Path, prefix: str) -> None:
    """Install the bundled pip wheel into the target prefix."""
    lib = next(stage.glob("**/lib/python3.14"))
    wheel = next((lib / "ensurepip" / "_bundled").glob("pip-*.whl"))
    site_packages = lib / "site-packages"
    with zipfile.ZipFile(wheel) as archive:
        archive.extractall(site_packages)
    bin_dir = stage / prefix.lstrip("/") / "bin"
    for name in ("pip", "pip3", "pip3.14"):
        script = bin_dir / name
        script.write_text(
            f"#!{prefix}/bin/python3.14\n"
            "import sys\n"
            "from pip._internal.cli.main import main\n"
            "if __name__ == '__main__':\n"
            "    sys.exit(main())\n",
            encoding="utf-8",
        )
        script.chmod(0o755)


def clean_sysconfig(
    stage: Path, source: Path, deps: Path, host: Path
) -> None:
    """Remove build-machine paths from installed build metadata."""
    lib = next(stage.glob("**/lib/python3.14"))
    replacements = {
        str(source): "/usr/src/cpython",
        str(deps): "/usr/local",
        str(host): "python3.14",
        "/Users/runner/hostedtoolcache": "/usr/local",
    }
    for path in lib.glob("_sysconfigdata_*.py"):
        text = path.read_text(encoding="utf-8")
        for old, new in replacements.items():
            text = text.replace(old, new)
        path.write_text(text, encoding="utf-8")
        for bytecode in (lib / "__pycache__").glob(f"{path.stem}*.pyc"):
            bytecode.unlink()
    for path in lib.glob("_sysconfig_vars_*.json"):
        path.unlink()
    (lib / "build-details.json").unlink(missing_ok=True)


def deb(
    name: str,
    stage: Path,
    output: Path,
    epoch: int,
    architecture: str,
) -> Path:
    layout = name.rsplit("-", 1)[-1]
    control = Path(tempfile.mkdtemp(prefix="control-", dir=stage.parent))
    try:
        (control / "control").write_text(
            f"Package: {name}\nVersion: {PACKAGE_VERSION}\n"
            f"Architecture: {architecture}\nMaintainer: k1tty-xz\n"
            "Name: Python 3.14\nSection: Development\n"
            f"Description: Standalone CPython {PYTHON_VERSION} for jailbroken iOS ({layout}).\n",
            encoding="utf-8",
        )
        output.mkdir(parents=True, exist_ok=True)
        package = output / f"{name}_{PACKAGE_VERSION}_{architecture}.deb"
        with package.open("wb") as file:
            file.write(b"!<arch>\n")
            file.write(member("debian-binary", b"2.0\n", epoch))
            file.write(member("control.tar.gz", tar_gz(control, epoch), epoch))
            file.write(member("data.tar.gz", tar_gz(stage, epoch), epoch))
        return package
    finally:
        shutil.rmtree(control, ignore_errors=True)


def build(
    source: Path,
    work: Path,
    deps: Path,
    host: Path,
    env: Mapping[str, str],
    jobs: int,
    name: str,
    prefix: str,
    architecture: str,
    output: Path,
    epoch: int,
) -> Path:
    directory = work / name
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    build_source = directory / "source"
    shutil.copytree(
        source,
        build_source,
        symlinks=True,
        ignore=shutil.ignore_patterns(".git"),
    )
    command = [
        build_source / "configure",
        f"--host={IOS_HOST}",
        f"--build={get([build_source / 'config.guess'])}",
        f"--with-build-python={host}",
        f"--prefix={prefix}",
        "--disable-framework",
        "--disable-test-modules",
        "--with-system-libmpdec",
        "--with-ensurepip=no",
        f"--with-openssl={deps}",
        f"LIBLZMA_CFLAGS=-I{deps / 'include'}",
        f"LIBLZMA_LIBS=-L{deps / 'lib'} -llzma",
        f"LIBFFI_CFLAGS=-I{deps / 'include'}",
        f"LIBFFI_LIBS=-L{deps / 'lib'} -lffi",
        f"LIBMPDEC_CFLAGS=-I{deps / 'include'}",
        f"LIBMPDEC_LIBS=-L{deps / 'lib'} -lmpdec",
        f"LIBZSTD_CFLAGS=-I{deps / 'include'}",
        f"LIBZSTD_LIBS=-L{deps / 'lib'} -lzstd",
    ]
    build_env = env | {
        "CPPFLAGS": f"{env['CPPFLAGS']} -I{deps / 'include'}",
        "LDFLAGS": f"-L{deps / 'lib'}",
    }
    run(command, cwd=build_source, env=build_env)
    run(
        ["make", "-j", str(jobs), "build_all"], cwd=build_source, env=build_env
    )
    stage = directory / "stage"
    run(
        ["make", "install", f"DESTDIR={stage}"],
        cwd=build_source,
        env=build_env,
    )
    binary = next(stage.glob("**/bin/python3.14"))
    header = get(["otool", "-hv", binary]).lower()
    linked = get(["otool", "-L", binary]).lower()
    if "arm64" not in header or "python.framework" in linked:
        raise RuntimeError("unexpected interpreter linkage")
    install_pip(stage, prefix)
    clean_sysconfig(stage, build_source, deps, host)
    sign(stage)
    return deb(name, stage, output, epoch, architecture)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-ios", default="13.0")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--work", type=Path, default=Path(".build"))
    parser.add_argument("--output", type=Path, default=Path("dist"))
    args = parser.parse_args()
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
    args.work = args.work.resolve()
    args.output = args.output.resolve()
    source = args.work / "cpython"
    if source.exists():
        shutil.rmtree(source)
    run(
        [
            "git",
            "clone",
            "--depth",
            "1",
            "--branch",
            f"v{PYTHON_VERSION}",
            "https://github.com/python/cpython.git",
            source,
        ]
    )
    if get(["git", "-C", source, "rev-parse", "HEAD"]) != CPYTHON_SHA:
        raise RuntimeError("unexpected CPython source")
    patch(source)
    deps = args.work / "dependencies"
    dependencies(deps, args.work / "downloads")
    host = host_python()
    env = ios_env(source, args.min_ios, epoch)
    for name, prefix, architecture in (
        ("python3-ios-rootful", "/usr/local", "iphoneos-arm"),
        ("python3-ios-rootless", "/var/jb/usr/local", "iphoneos-arm64"),
    ):
        print(
            build(
                source,
                args.work,
                deps,
                host,
                env,
                args.jobs,
                name,
                prefix,
                architecture,
                args.output,
                epoch,
            )
        )


if __name__ == "__main__":
    main()
