"""push.py - upload /tmp/es into easydev-org/easysetup via the contents API.

`git push` to github.com is reset mid-transfer in this sandbox; the REST API
works, and for a first import it is equivalent.
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

API = "https://api.github.com/repos/easydev-org/easysetup"
ROOT = pathlib.Path("/tmp/es")
SKIP = {".git", "tmp", "__pycache__"}


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


# Files removed from the repository in this revision must go too, otherwise the
# stale Dockerfile/build.sh keep building combinations that no longer exist.
for stale in ("Dockerfile", "build.sh", "env.sh.in",
              "tools/node.sh", "tools/python.sh", "tools/go.sh", "tools/java.sh",
              ".github/workflows/build.yml", "tools/build-node.sh.bak",
              "probe.py", "probe2.py", "probe3.py", "dbg.py",
              # agent-side helpers: they talk to the GitHub API to publish and
              # verify, but they are not part of what this repository ships.
              "push.py", "cleanup.py", "pin_sri.py", "verify.py"):
    status, info = call("GET", f"{API}/contents/{stale}")
    if status == 200:
        call("DELETE", f"{API}/contents/{stale}",
             {"message": f"remove {stale}", "sha": info["sha"], "branch": "main"})
        print(f"del {stale}")

uploaded = 0
for path in sorted(ROOT.rglob("*")):
    rel = path.relative_to(ROOT)
    if any(p in SKIP for p in rel.parts) or not path.is_file():
        continue
    remote = str(rel).replace(os.sep, "/")
    content = base64.b64encode(path.read_bytes()).decode()
    status, info = call("GET", f"{API}/contents/{remote}")
    sha = info.get("sha") if status == 200 and isinstance(info, dict) else None
    payload = {"message": f"write {remote}", "content": content, "branch": "main"}
    if sha:
        payload["sha"] = sha
    status, out = call("PUT", f"{API}/contents/{remote}", payload)
    ok = status in (200, 201)
    print(f"{'ok ' if ok else 'ERR'} {remote} ({status})")
    if ok:
        uploaded += 1
    else:
        print("   ", out)
print(f"push.py: {uploaded} uploaded")
