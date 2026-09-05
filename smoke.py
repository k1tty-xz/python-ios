"""Run with the installed interpreter on a jailbroken device: python3 smoke.py."""

import asyncio
import bz2
import concurrent.futures
import ctypes
import hashlib
import importlib
import json
import lzma
import multiprocessing
import os
from pathlib import Path
import platform
import sqlite3
import ssl
import subprocess
import sys
import sysconfig
import tempfile
import time
import urllib.request
import venv
import zlib


def square(value):
    return value * value


def main():
    assert sys.platform == "ios", sys.platform
    assert sysconfig.get_platform() == "ios-14.0-arm64-iphoneos"
    print(sys.version, flush=True)
    print(platform.ios_ver(), flush=True)
    for name in ("_ssl", "_hashlib", "_ctypes", "_sqlite3", "_bz2", "_lzma",
                 "zlib", "_posixsubprocess", "_multiprocessing", "_socket",
                 "select", "fcntl", "termios", "resource", "pwd", "grp"):
        importlib.import_module(name)
    print("PASS native standard-library imports", flush=True)
    import _native_check
    assert _native_check.answer() == 42
    print("PASS external C extension import", flush=True)

    payload = b"Python on a jailbroken iPhone\x00" * 1000
    for codec in (zlib, bz2, lzma):
        assert codec.decompress(codec.compress(payload)) == payload
    assert hashlib.sha256(b"abc").hexdigest() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    with sqlite3.connect(":memory:") as db:
        db.execute("CREATE TABLE sample (value BLOB)")
        db.execute("INSERT INTO sample VALUES (?)", (payload,))
        assert db.execute("SELECT value FROM sample").fetchone()[0] == payload
    print("PASS compression, hashing and SQLite", flush=True)
    previous_tz = os.environ.get("TZ")
    try:
        os.environ["TZ"] = "UTC+0"
        time.tzset()
        assert time.localtime(0).tm_hour == 0
        os.environ["TZ"] = "UTC-2"
        time.tzset()
        assert time.localtime(0).tm_hour == 2
    finally:
        if previous_tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = previous_tz
        time.tzset()
    print("PASS timezone switching", flush=True)

    libc = ctypes.CDLL(None)
    libc.getpid.restype = ctypes.c_int
    assert libc.getpid() == os.getpid()
    callback = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int)(square)
    assert callback(7) == 49
    print("PASS ctypes calls and callbacks", flush=True)

    result = subprocess.run([sys.executable, "-c", "print('child')"],
                            capture_output=True, text=True, check=True, timeout=20)
    assert result.stdout == "child\n", repr(result.stdout)
    assert subprocess.check_output("printf shell", shell=True, timeout=20) == b"shell"
    assert os.system("/bin/sh -c 'exit 0'") == 0
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        assert list(pool.map(square, [2, 3])) == [4, 9]
    with concurrent.futures.ProcessPoolExecutor(2, mp_context=multiprocessing.get_context("spawn")) as pool:
        assert list(pool.map(square, [2, 3])) == [4, 9]
    asyncio.run(asyncio.sleep(0.01))
    print("PASS subprocess, shell, threads, multiprocessing and asyncio", flush=True)

    context = ssl.create_default_context()
    assert context.cert_store_stats()["x509_ca"] > 0
    with urllib.request.urlopen("https://pypi.org/pypi/pip/json", context=context, timeout=30) as response:
        assert json.load(response)["info"]["name"] == "pip"
    print("PASS verified HTTPS to PyPI:", ssl.OPENSSL_VERSION, flush=True)

    with tempfile.TemporaryDirectory(prefix="python-ios-test-") as temporary:
        directory = Path(temporary) / "venv"
        venv.EnvBuilder(with_pip=True).create(directory)
        python = str(directory / "bin/python")
        subprocess.run([python, "-m", "pip", "install", "--disable-pip-version-check",
                        "packaging==26.2"], check=True, timeout=120)
        subprocess.run([python, "-c", "import packaging, sys; assert sys.prefix != sys.base_prefix; "
                        "from packaging.tags import sys_tags; tags=list(sys_tags()); "
                        "assert any(t.platform.startswith('ios_') for t in tags); "
                        "assert not any('macosx' in t.platform for t in tags); print(tags[0])"],
                       check=True, timeout=30)
    print("PASS venv, pip installation and iOS wheel tags", flush=True)
    print("ALL CHECKS PASSED", flush=True)


if __name__ == "__main__":
    main()
