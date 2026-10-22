"""verify.py — prove matrix.yml's pins match the published assets.

install.sh refuses to unpack on a checksum mismatch, so a wrong pin means a
setup nobody can install. This checks every entry: the release exists, carries
the named artefact, and GitHub's own digest equals the pin.
"""

import json
import os
import re
import sys
import urllib.request

TOKEN = ""
for line in open(os.path.expanduser("~/.config/gh/hosts.yml")):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

API = "https://api.github.com/repos/easydev-org/easysetup"


def get(url):
    req = urllib.request.Request(url, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
    })
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.load(r)


text = open("/tmp/mx.yml").read()
entries, cur = {}, None
for line in text.splitlines():
    m = re.match(r"^  ([a-z0-9-]+):$", line)
    if m:
        cur = m.group(1)
        entries[cur] = {}
        continue
    if cur:
        for f in ("version", "artifact", "sha256"):
            m2 = re.match(rf'^\s+{f}:\s*"?([^"#]*)"?', line)
            if m2:
                entries[cur][f] = m2.group(1).strip()

releases = {r["tag_name"]: r for r in get(API + "/releases?per_page=100")}

bad = 0
for sid, e in entries.items():
    ver, art, pin = e.get("version"), e.get("artifact"), e.get("sha256")
    tag = f"{sid}-{ver}"
    rel = releases.get(tag)
    if not rel:
        print(f"FAIL {sid}: no release {tag}"); bad += 1; continue
    asset = next((a for a in rel["assets"] if a["name"] == art), None)
    if not asset:
        print(f"FAIL {sid}: {tag} has no {art}"); bad += 1; continue
    digest = (asset.get("digest") or "").replace("sha256:", "")
    if not pin or not digest or pin != digest:
        print(f"FAIL {sid}: pin {pin[:12]}... != asset {digest[:12]}..."); bad += 1; continue
    print(f"ok   {sid:12} {asset['size']:>10}  {pin[:16]}...")

print(f"\nverify.py: {len(entries)} entries, {bad} problem(s)")
sys.exit(1 if bad else 0)
