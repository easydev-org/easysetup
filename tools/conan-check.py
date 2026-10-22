#!/usr/bin/env python3
"""Import every module conan needs, from the staged lib/. Fails loudly.

Conan's wheel does not carry its dependencies, so the build vendors them. This
is the check that the vendoring is actually complete: importing only `conan`
would miss `colorama`, which is where the first attempt died.

    conan-check.py <staged-lib-dir>
"""

import os
import sys


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    lib = argv[1]
    if not os.path.isdir(lib):
        sys.exit("conan-check: %s is not a directory" % lib)
    sys.path.insert(0, lib)

    # Every Requires-Dist of conan 2.33, plus the names their imports use.
    modules = [
        "conan",
        "colorama",
        "yaml",              # PyYAML
        "requests",
        "urllib3",
        "jinja2",
        "dateutil",
        "distro",
        "fasteners",
        "patch_ng",
        "truststore",
        "certifi",
        "idna",
        "charset_normalizer",
        "markupsafe",
    ]
    missing = []
    for m in modules:
        try:
            __import__(m)
        except Exception as e:
            missing.append((m, type(e).__name__, str(e)))
    # The CLI entry point itself, which pulls in the rest of conan's tree.
    try:
        from conans.conan import run  # noqa: F401
    except Exception as e:
        missing.append(("conans.conan:run", type(e).__name__, str(e)))

    if missing:
        for m, kind, err in missing:
            print("  MISSING %-20s %s: %s" % (m, kind, err[:80]), file=sys.stderr)
        return 1
    print("conan-check: all %d module(s) import from %s" % (len(modules), lib))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
