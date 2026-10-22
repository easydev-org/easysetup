"""pin_sri.py — fill every sha256 in matrix.yml from the published assets.

The release workflow computes these itself, but that step races with any other
push to main. Running this by hand (or after a lost race) makes matrix.yml
correct without rebuilding anything.
"""

import hashlib
import json
import os
import pathlib
import re
import urllib.error
import urllib.request

TOKEN = ""
for line in open(os.path.expanduser("~/.config/gh/hosts.yml")):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

REPO = "easydev-org/easysetup"
API = f"https://api.github.com/repos/{REPO}"
ROOT = pathlib.Path("/tmp/es")


def api(path):
    req = urllib.request.Request(API + path, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
    })
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.load(r)


text = (ROOT / "matrix.yml").read_text()

# id -> (version, artifact) straight from the file, so we look up exactly what
# the manifest claims.
entries = {}
cur = None
for line in text.splitlines():
    m = re.match(r"^  ([a-z0-9-]+):$", line)
    if m:
        cur = m.group(1)
        entries[cur] = {}
        continue
    if cur:
        for f in ("version", "artifact"):
            m2 = re.match(rf"^\s+{f}:\s*\"?([^\"]*)\"?\s*$", line)
            if m2:
                entries[cur][f] = m2.group(1).strip()

releases = {r["tag_name"]: r for r in api("/releases?per_page=100")}

changed = 0
for sid, info in entries.items():
    ver, artifact = info.get("version"), info.get("artifact")
    if not ver or not artifact:
        print(f"skip {sid}: incomplete")
        continue
    tag = f"{sid}-{ver}"
    rel = releases.get(tag)
    if not rel:
        print(f"skip {sid}: no release {tag}")
        continue
    asset = next((a for a in rel["assets"] if a["name"] == artifact), None)
    if not asset:
        print(f"skip {sid}: release {tag} has no asset {artifact}")
        continue

    # GitHub publishes a digest for the asset; trust it over re-downloading.
    digest = (asset.get("digest") or "").replace("sha256:", "")
    if not digest:
        with urllib.request.urlopen(
            urllib.request.Request(asset["browser_download_url"],
                                   headers={"Authorization": "Bearer " + TOKEN}),
            timeout=600) as r:
            digest = hashlib.sha256(r.read()).hexdigest()

    pattern = re.compile(
        r'(  ' + re.escape(sid) + r':\n(?:.*\n)*?\s+artifact: ' +
        re.escape(artifact) + r'\n\s+sha256: )"[^"]*"')
    text, n = pattern.subn(r'\1"' + digest + '"', text, count=1)
    print(f"{sid:12} {asset['size']:>10} bytes  sha256={digest[:16]}...  ({n} pinned)")
    changed += n

(ROOT / "matrix.yml").write_text(text)
print(f"pin_sri.py: {changed} checksum(s) pinned")
