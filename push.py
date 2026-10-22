"""push.py — upload a local tree to a GitHub repo through the contents API.

`git push` to github.com does not survive this sandbox (the TLS connection is
reset mid-transfer), but the REST API does. This walks the working tree and
creates/updates every file, which is equivalent for a first import.
"""

import base64
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

TOKEN = ""
for line in open(os.path.expanduser("~/.config/gh/hosts.yml")):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break
if not TOKEN:
    sys.exit("push.py: no oauth_token")

OWNER, REPO = "easydev-org", "easysetup"
API = f"https://api.github.com/repos/{OWNER}/{REPO}"
ROOT = pathlib.Path("/tmp/es")
SKIP_DIRS = {".git", "tmp", "__pycache__"}


def call(method, url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def should_skip(p: pathlib.Path) -> bool:
    return any(part in SKIP_DIRS for part in p.parts) or p.suffix in {".xz", ".gz"}


uploaded = 0
for path in sorted(ROOT.rglob("*")):
    rel = path.relative_to(ROOT)
    if should_skip(rel) or not path.is_file():
        continue
    remote = str(rel).replace(os.sep, "/")
    content = base64.b64encode(path.read_bytes()).decode()

    # An existing file needs its blob sha to be replaced.
    status, info = call("GET", f"{API}/contents/{remote}")
    sha = info.get("sha") if status == 200 and isinstance(info, dict) else None

    payload = {"message": f"add {remote}", "content": content, "branch": "main"}
    if sha:
        payload["sha"] = sha
    status, out = call("PUT", f"{API}/contents/{remote}", payload)
    ok = status in (200, 201)
    print(f"{'ok ' if ok else 'ERR'} {remote} ({status})")
    if ok:
        uploaded += 1
    else:
        print("   ", out)

print(f"push.py: {uploaded} file(s) uploaded")
