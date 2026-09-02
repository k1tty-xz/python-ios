#!/usr/bin/env python3
"""Build rootful and rootless CPython Debian packages for jailbroken iOS."""

from __future__ import annotations

import argparse
import gzip
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path


CPYTHON_REF = "v3.14.7"
CPYTHON_SHA = "823f0323ee6ec1402088b73bce1a38473cac36dc"
DEPS = (
    "BZip2-1.0.8-2", "libFFI-3.4.7-2", "OpenSSL-3.5.7-1",
    "XZ-5.6.4-2", "mpdecimal-4.0.0-2", "zstd-1.5.7-1",
)
DEPS_URL = "https://github.com/beeware/cpython-apple-source-deps/releases/download"


def run(command, *, cwd=None, env=None):
    print("+", " ".join(map(str, command)))
    subprocess.run(command, cwd=cwd, env=env, check=True)


def get(command):
    return subprocess.check_output(command, text=True).strip()


def replace(path, old, new, count=1):
    text = path.read_text(encoding="utf-8")
    if text.count(old) != count:
        raise RuntimeError(f"unexpected {path}: {old!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def patch(source):
    configure = source / "configure"
    replace(configure, '\t\t\tiOS) as_fn_error $? "iOS builds must use --enable-framework" "$LINENO" 5 ;;\n', "")
    replace(configure, '\t\tiOS) as_fn_error $? "iOS builds must use --enable-framework" "$LINENO" 5 ;;\n', "")
    replace(configure,
        "\tiOS/*)\n\t\tLDSHARED='$(CC) -dynamiclib -F . -framework $(PYTHONFRAMEWORK)'\n\t\tLDCXXSHARED='$(CXX) -dynamiclib -F . -framework $(PYTHONFRAMEWORK)'\n\t\tBLDSHARED=\"$LDSHARED\"\n",
        "\tiOS/*)\n\t\tLDSHARED='$(CC) -bundle -undefined dynamic_lookup'\n\t\tLDCXXSHARED='$(CXX) -bundle -undefined dynamic_lookup'\n\t\tBLDSHARED=\"$LDSHARED\"\n")
    replace(configure, "\tDarwin/*|iOS/*)\n\t\tLINKFORSHARED=\"$extra_undefs -framework CoreFoundation\"\n", "\tDarwin/*)\n\t\tLINKFORSHARED=\"$extra_undefs -framework CoreFoundation\"\n")
    replace(configure, 'if test "$ac_sys_system" = "iOS"; then\n  MODULE_DEPS_SHARED="$MODULE_DEPS_SHARED \\$(PYTHONFRAMEWORKDIR)/\\$(PYTHONFRAMEWORK)"\nfi\n', 'if test "$ac_sys_system" = "iOS" && test "$enable_framework"; then\n  MODULE_DEPS_SHARED="$MODULE_DEPS_SHARED \\$(PYTHONFRAMEWORKDIR)/\\$(PYTHONFRAMEWORK)"\nfi\n')
    text = configure.read_text(encoding="utf-8")
    text, count = re.subn(r"(  iOS\) :\n).*?(\n   ;; #\(\n  CYGWIN\*\) :)", r"\1\n\n    py_cv_module__scproxy=n/a\n\2", text, count=1, flags=re.DOTALL)
    if count != 1:
        raise RuntimeError("unexpected iOS extension-module block")
    configure.write_text(text, encoding="utf-8")
    replace(source / "Lib/subprocess.py", 'sys.platform not in {"emscripten", "wasi", "ios", "tvos", "watchos"}', 'sys.platform not in {"emscripten", "wasi", "tvos", "watchos"}')
    replace(source / "Lib/site.py", 'Emscripten, iOS, tvOS, VxWorks, WASI, and watchOS', 'Emscripten, tvOS, VxWorks, WASI, and watchOS')
    replace(source / "Lib/site.py", '{"emscripten", "ios", "tvos", "vxworks", "wasi", "watchos"}', '{"emscripten", "tvos", "vxworks", "wasi", "watchos"}')
    replace(source / "Lib/sysconfig/__init__.py", 'Emscripten, iOS, tvOS, VxWorks, WASI, and watchOS', 'Emscripten, tvOS, VxWorks, WASI, and watchOS')
    replace(source / "Lib/sysconfig/__init__.py", '{"emscripten", "ios", "tvos", "vxworks", "wasi", "watchos"}', '{"emscripten", "tvos", "vxworks", "wasi", "watchos"}')


def dependencies(prefix, cache):
    prefix.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    for dep in DEPS:
        name = f"{dep.lower()}-iphoneos.arm64.tar.gz"
        archive = cache / name
        if not archive.exists():
            urllib.request.urlretrieve(f"{DEPS_URL}/{dep}/{name}", archive)
        shutil.unpack_archive(archive, prefix)
    for dylib in prefix.rglob("*.dylib"):
        dylib.unlink()


def host_python():
    if sys.version_info[:3] != (3, 14, 7):
        raise RuntimeError("the build requires Python 3.14.7")
    return Path(sys.executable).resolve()


def ios_env(source, min_ios, epoch):
    return os.environ | {
        "PATH": f"{source / 'Apple/iOS/Resources/bin'}:{os.environ['PATH']}",
        "CPPFLAGS": "-D_DARWIN_C_SOURCE",
        "IPHONEOS_DEPLOYMENT_TARGET": min_ios,
        "SOURCE_DATE_EPOCH": str(epoch),
    }


def tar_gz(root, epoch):
    stream = io.BytesIO()
    with gzip.GzipFile(fileobj=stream, mode="wb", mtime=epoch) as zipped, tarfile.open(fileobj=zipped, mode="w:") as tar:
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


def member(name, data, epoch):
    header = (f"{name}/".ljust(16) + f"{epoch}".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8) + f"{len(data)}".ljust(10) + "`\n").encode()
    return header + data + (b"\n" if len(data) % 2 else b"")


def deb(name, stage, output, epoch):
    control = stage.parent / "control"
    control.mkdir()
    (control / "control").write_text(f"Package: {name}\nVersion: 3.14.7\nArchitecture: iphoneos-arm64\nMaintainer: k1tty-xz\nDescription: CPython for a jailbroken iOS root filesystem\n", encoding="utf-8")
    output.mkdir(parents=True, exist_ok=True)
    package = output / f"{name}_3.14.7_iphoneos-arm64.deb"
    with package.open("wb") as file:
        file.write(b"!<arch>\n")
        file.write(member("debian-binary", b"2.0\n", epoch))
        file.write(member("control.tar.gz", tar_gz(control, epoch), epoch))
        file.write(member("data.tar.gz", tar_gz(stage, epoch), epoch))
    shutil.rmtree(control)
    return package


def build(source, work, deps, host, env, jobs, name, prefix, output, epoch):
    directory = work / name
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    build_source = directory / "source"
    shutil.copytree(source, build_source, symlinks=True)
    command = [build_source / "configure", "--host=arm64-apple-ios", f"--build={get([build_source / 'config.guess'])}", f"--with-build-python={host}", f"--prefix={prefix}", "--disable-framework", "--with-app-store-compliance=", "--with-system-libmpdec", "--with-ensurepip=upgrade", f"--with-openssl={deps}", f"LIBLZMA_CFLAGS=-I{deps / 'include'}", f"LIBLZMA_LIBS=-L{deps / 'lib'} -llzma", f"LIBFFI_CFLAGS=-I{deps / 'include'}", f"LIBFFI_LIBS=-L{deps / 'lib'} -lffi", f"LIBMPDEC_CFLAGS=-I{deps / 'include'}", f"LIBMPDEC_LIBS=-L{deps / 'lib'} -lmpdec", f"LIBZSTD_CFLAGS=-I{deps / 'include'}", f"LIBZSTD_LIBS=-L{deps / 'lib'} -lzstd"]
    build_env = env | {"CPPFLAGS": f"{env['CPPFLAGS']} -I{deps / 'include'}", "LDFLAGS": f"-L{deps / 'lib'}"}
    run(command, cwd=build_source, env=build_env)
    run(["make", "-j", str(jobs), "build_all"], cwd=build_source, env=build_env)
    stage = directory / "stage"
    run(["make", "install", f"DESTDIR={stage}"], cwd=build_source, env=build_env)
    binary = next(stage.glob("**/bin/python3.14"))
    if "arm64" not in get(["otool", "-hv", binary]) or "Framework" in get(["otool", "-L", binary]):
        raise RuntimeError("unexpected interpreter linkage")
    return deb(name, stage, output, epoch)


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
    run(["git", "clone", "--depth", "1", "--branch", CPYTHON_REF, "https://github.com/python/cpython.git", source])
    if get(["git", "-C", source, "rev-parse", "HEAD"]) != CPYTHON_SHA:
        raise RuntimeError("unexpected CPython source")
    patch(source)
    deps = args.work / "dependencies"
    dependencies(deps, args.work / "downloads")
    host = host_python()
    env = ios_env(source, args.min_ios, epoch)
    for name, prefix in (("python3-ios-rootful", "/usr/local"), ("python3-ios-rootless", "/var/jb/usr/local")):
        print(build(source, args.work, deps, host, env, args.jobs, name, prefix, args.output, epoch))


if __name__ == "__main__":
    main()
