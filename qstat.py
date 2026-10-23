"""Summarise the newest nix-release run: overall, then per-job."""

import json
import subprocess
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


run = None
for r in gh("/actions/runs?per_page=5").get("workflow_runs", []):
    if r["name"] == "nix-release":
        run = r
        break
if run is None:
    raise SystemExit("no nix-release run found")

print("run %s  %s %s" % (run["id"], run["status"], run["conclusion"]))
jobs = gh("/actions/runs/%s/jobs?per_page=100" % run["id"]).get("jobs", [])
counts = Counter()
failed = []
for j in jobs:
    key = (j["status"], j["conclusion"])
    counts[key] += 1
    if j["conclusion"] == "failure":
        failed.append(j["name"])
for (st, con), n in sorted(counts.items(), key=lambda x: -x[1]):
    print("  %-12s %-10s %d" % (st, con, n))
print()
print("total jobs:", len(jobs))
if failed:
    print("failed (%d):" % len(failed))
    for f in failed:
        print("   ", f)
