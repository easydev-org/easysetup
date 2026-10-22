"""Cancel all but the newest release run, and report it."""

import json
import os
import urllib.request

TOKEN = ""
for line in open(os.path.expanduser("~/.config/gh/hosts.yml")):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

API = "https://api.github.com/repos/easydev-org/easysetup"


def call(method, path):
    req = urllib.request.Request(API + path, method=method, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read()
        return r.status, (json.loads(body) if body else None)


runs = call("GET", "/actions/runs?per_page=40")[1]["workflow_runs"]
active = [r for r in runs if r["name"] == "release" and r["status"] != "completed"]
active.sort(key=lambda r: r["created_at"], reverse=True)

print("active:", len(active))
if not active:
    raise SystemExit(0)
keep = active[0]
print("KEEP", keep["id"], keep["head_sha"][:8], keep["created_at"])
for r in active[1:]:
    st, _ = call("POST", f"/actions/runs/{r['id']}/cancel")
    print("  cancel", r["id"], r["head_sha"][:8], st)
