#!/usr/bin/env python3
"""Remove .tar.xz assets, keeping any .tar.zst that sits beside them.

The first version of this script deleted whole releases whose assets were all
.tar.xz. That missed the case that matters: a setup rebuilt after the switch has
BOTH files under one tag, so "all assets are xz" is false and nothing was pruned.
Deleting per-asset is the correct granularity.

install.sh fetches `<dir>-debian-trixie-amd64.tar.zst` by name, so a leftover
`.tar.xz` is dead weight - it cannot be picked up by accident, but it doubles the
storage for every setup that was rebuilt.

    tools/purge-xz-assets.py [--apply]
"""

import json
import subprocess
import sys

TOKEN = ""
for line in open("/root/.config/gh/hosts.yml"):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

API = "https://api.github.com/repos/easydev-org/easysetup"


def gh(method, path):
    out = subprocess.run(
        ["curl", "-sSL", "--max-time", "90", "-X", method,
         "-H", "Authorization: Bearer " + TOKEN,
         "-H", "Accept: application/vnd.github+json", API + path],
        capture_output=True, text=True).stdout
    try:
        return json.loads(out) if out.strip() else {}
    except Exception:
        return {}


def main(argv):
    apply = "--apply" in argv
    orphan_tags = []   # releases that will have nothing left
    victims = []       # (release, asset)
    page = 1
    while True:
        rs = gh("GET", "/releases?per_page=100&page=%d" % page)
        if not isinstance(rs, list) or not rs:
            break
        for r in rs:
            assets = r.get("assets", [])
            xz = [a for a in assets if a["name"].endswith(".tar.xz")
                  or a["name"].endswith(".tar.xz.sha256")]
            survivors = [a for a in assets if a not in xz]
            for a in xz:
                victims.append((r, a))
            if xz and not survivors:
                orphan_tags.append(r)
        page += 1

    print("xz assets to remove: %d" % len(victims))
    print("releases left empty afterwards: %d" % len(orphan_tags))
    print("releases that keep a .zst: %d" % (len({v[0]['id'] for v in victims}) - len(orphan_tags)))
    if not apply:
        print()
        print("rerun with --apply to delete them")
        return 0

    n = 0
    for r, a in victims:
        gh("DELETE", "/releases/assets/%d" % a["id"])
        n += 1
        if n % 20 == 0:
            print("   removed %d/%d" % (n, len(victims)))
    print("removed %d asset(s)" % n)

    for r in orphan_tags:
        gh("DELETE", "/releases/%d" % r["id"])
        gh("DELETE", "/git/refs/tags/%s" % r["tag_name"])
    print("deleted %d empty release(s) and their tags" % len(orphan_tags))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
