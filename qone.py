"""Print the failure reason of one job, and the shapes other failures share."""

import json
import subprocess
import sys
from collections import Counter

TOKEN = ""
for line in open("/root/.config/gh/hosts.yml"):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

API = "https://api.github.com/repos/easydev-org/easysetup"


def gh(p):
    out = subprocess.run(
        ["curl", "-sSL", "--max-time", "90", "-H",
         "Authorization: Bearer " + TOKEN, API + p],
        capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}


run = sys.argv[1] if len(sys.argv) > 1 else ""
if not run:
    for r in gh("/actions/runs?per_page=5").get("workflow_runs", []):
        if r["name"] == "nix-release":
            run = r["id"]
            break

jobs = gh("/actions/runs/%s/jobs?per_page=100" % run).get("jobs", [])
failed = [j for j in jobs if j["conclusion"] == "failure"]
print("failed jobs: %d" % len(failed))

# The first failing STEP tells you whether this is one bug or many.
steps = Counter()
for j in failed:
    for s in j.get("steps", []):
        if s["conclusion"] == "failure":
            steps[s["name"]] += 1
print("failing steps:", dict(steps))

if not failed:
    raise SystemExit(0)

# Read two logs and collect error-looking lines, which should be enough to spot a
# shared cause without pulling 63 logs.
for j in failed[:2]:
    print()
    print("=====", j["name"])
    log = subprocess.run(
        ["curl", "-sSL", "--max-time", "90", "-H",
         "Authorization: Bearer " + TOKEN,
         API + "/actions/jobs/%s/logs" % j["id"]],
        capture_output=True, text=True).stdout
    lines = [l.split("Z ", 1)[-1] for l in log.splitlines()
             if "##[" not in l and "\x1b[36;1m" not in l]
    keep = [l for l in lines if any(
        k in l for k in ("nixpkg:", "error:", "error ", "cannot", "not found",
                         "No such", "failed"))]
    for l in keep[-18:]:
        print("   ", l[:190])
