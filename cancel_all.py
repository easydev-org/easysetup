"""Cancel EVERY queued/in-progress release run (there are dozens)."""

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


total = 0
while True:
    runs = call("GET", "/actions/runs?per_page=100")[1]["workflow_runs"]
    active = [r for r in runs if r["status"] != "completed"]
    if not active:
        break
    for r in active:
        st, _ = call("POST", f"/actions/runs/{r['id']}/cancel")
        total += 1
        print("cancel", r["id"], r["name"], r["status"], st)
    if len(active) < 100:
        break

print("cancelled", total)
