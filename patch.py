"""Small, checked adaptations of upstream CPython for a jailbreak CLI."""

import pathlib
import sys


def replace(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f"Upstream changed: expected one match in {path}")
    path.write_text(text.replace(old, new))


source = pathlib.Path(sys.argv[1])

# A terminal owns stdin/stdout/stderr; don't redirect them to Apple's app log.
replace(source / "Python/initconfig.c",
        "#define USE_SYSTEM_LOGGER_DEFAULT 1;",
        "#define USE_SYSTEM_LOGGER_DEFAULT 0;")

# The configure probes decide which POSIX functions exist on the jailbreak.
replace(source / "Lib/subprocess.py",
        '{"emscripten", "wasi", "ios", "tvos", "watchos"}',
        '{"emscripten", "wasi", "tvos", "watchos"}')
for name in ("Lib/site.py", "Lib/sysconfig/__init__.py"):
    replace(source / name,
            '{"emscripten", "ios", "tvos", "vxworks", "wasi", "watchos"}',
            '{"emscripten", "tvos", "vxworks", "wasi", "watchos"}')

# Use the same safe multiprocessing default as macOS.
replace(source / "Lib/multiprocessing/context.py",
        "sys.platform != 'darwin'", "sys.platform not in {'darwin', 'ios'}")

# A command-line process does not load UIKit. Read the OS version directly,
# avoiding a GUI framework dependency just to compute pip's compatibility tags.
(source / "Lib/_ios_support.py").write_text('''import os
import plistlib


def get_platform_ios():
    with open("/System/Library/CoreServices/SystemVersion.plist", "rb") as stream:
        version = plistlib.load(stream)["ProductVersion"]
    model = os.uname().machine
    return ("iPadOS" if model.startswith("iPad") else "iOS", version, model, False)
''')
