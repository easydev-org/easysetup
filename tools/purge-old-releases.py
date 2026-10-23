#!/usr/bin/env python3
"""Delete every release that still carries a .tar.xz asset.

The .tar.xz releases are from the previous pipeline: they contain hand-repacked
upstream binaries laid out under /opt/setup, which the current install.sh does
not understand. Leaving them would let `install.sh <name>` fetch a tarball it
cannot unpack, so they are removed rather than left as traps.

A release is only deleted if ALL its assets are .tar.xz - anything that already
carries a .tar.zst belongs to the new pipeline and is kept.

    tools/purge-old-releases.py [--apply]

Without --apply it only lists what it would delete.
"""

import json
import subprocess
import sys

TOKEN = ""
for line in open("/root/.config/gh/hosts.yml"):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

REPO = "easydev-org/easysetup"
API = "https://api.github.com/repos/" + REPO


def gh(method, path, data=None):
    cmd = ["curl", "-sSL", "--max-time", "90", "-X", method,
           "-H", "Authorization: Bearer " + TOKEN,
           "-H", "Accept: application/vnd.github+json", API + path]
    if data:
        cmd += ["-d", json.dumps(data)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    try:
        return json.loads(out) if out.strip() else {}
    except Exception:
        return {}


def main(argv):
    apply = "--apply" in argv
    old = []
    page = 1
    while True:
        rs = gh("GET", "/releases?per_page=100&page=%d" % page)
        if not isinstance(rs, list) or not rs:
            break
        for r in rs:
            names = [a["name"] for a in r.get("assets", [])]
            if names and all(n.endswith(".tar.xz") for n in names):
                old.append(r)
        page += 1

    print("releases made only of .tar.xz: %d" % len(old))
    if not apply:
        for r in old[:10]:
            print("   would delete", r["tag_name"])
        if len(old) > 10:
            print("   ... and %d more" % (len(old) - 10))
        print()
        print("rerun with --apply to delete them")
        return 0

    deleted = 0
    for r in old:
        gh("DELETE", "/releases/%d" % r["id"])
        # The tag survives the release deletion and would keep showing up as an
        # unreleased tag, so remove it too.
        gh("DELETE", "/git/refs/tags/%s" % r["tag_name"])
        deleted += 1
        if deleted % 10 == 0:
            print("   deleted %d/%d" % (deleted, len(old)))
    print("deleted %d release(s) and their tags" % deleted)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
