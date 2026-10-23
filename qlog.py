"""Print the parts of a job's log that explain a failure, without the installer noise."""

import json
import subprocess
import sys

TOKEN = ""
for line in open("/root/.config/gh/hosts.yml"):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

API = "https://api.github.com/repos/easydev-org/easysetup"


def gh(p):
    out = subprocess.run(
        ["curl", "-sSL", "--max-time", "60", "-H",
         "Authorization: Bearer " + TOKEN, API + p],
        capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}


run = sys.argv[1]
want = sys.argv[2] if len(sys.argv) > 2 else ""
for j in gh("/actions/runs/%s/jobs?per_page=12" % run).get("jobs", []):
    if want and want not in j["name"]:
        continue
    print("=====", j["name"], j["conclusion"])
    log = subprocess.run(
        ["curl", "-sSL", "--max-time", "90", "-H",
         "Authorization: Bearer " + TOKEN,
         API + "/actions/jobs/%s/logs" % j["id"]],
        capture_output=True, text=True).stdout
    lines = [l.split("Z ", 1)[-1] for l in log.splitlines()]
    # Keep only lines with something to say.
    keep = []
    for l in lines:
        s = l.replace("\x1b[36;1m", "").replace("\x1b[0m", "").strip()
        if not s:
            continue
        if s.startswith("##["):
            continue
        if any(k in s for k in ("nixpkg:", "error:", "cannot", "not found",
                                "No such", "failed", "FAIL", "will be",
                                "paths built", "these ", "copying")):
            keep.append(s[:200])
    for l in keep[-40:]:
        print("  ", l)
