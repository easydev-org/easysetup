#!/usr/bin/env python3
"""Print the download URL of a project's newest pure-Python wheel.

Reading a wheel URL out of the PyPI JSON API is fiddly enough (no wheel for the
newest version, platform-specific tags, sdists mixed in) that doing it inline in
a shell function was unreadable - and the shell here has no heredocs.

    pypi-wheel-url.py <project> [<version>]
"""

import json
import sys
import urllib.request


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    pkg = argv[1]
    want = argv[2] if len(argv) > 2 else None

    url = "https://pypi.org/pypi/%s/json" % pkg
    req = urllib.request.Request(url, headers={"User-Agent": "easysetup"})
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.load(r)

    ver = want or d["info"]["version"]
    files = d["releases"].get(ver) or []

    def rank(f):
        name = f["filename"]
        # Prefer a universal wheel, then any wheel, then an sdist.
        if name.endswith("py3-none-any.whl"):
            return 0
        if name.endswith(".whl"):
            return 1
        return 2

    files = [f for f in files if f["filename"].endswith((".whl", ".tar.gz"))]
    if not files:
        sys.exit("pypi-wheel-url: no downloadable file for %s %s" % (pkg, ver))
    files.sort(key=rank)
    best = files[0]
    if not best["filename"].endswith(".whl"):
        sys.exit("pypi-wheel-url: only an sdist exists for %s %s" % (pkg, ver))
    print(best["url"])


if __name__ == "__main__":
    main(sys.argv)
