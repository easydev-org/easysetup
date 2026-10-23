"""Print the failing step and log tail for named build jobs of a run."""

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
        ["curl", "-sSL", "--max-time", "90", "-H",
         "Authorization: Bearer " + TOKEN, API + p],
        capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}


run = sys.argv[1]
wants = sys.argv[2:]
for j in gh("/actions/runs/%s/jobs?per_page=100" % run).get("jobs", []):
    if j["conclusion"] != "failure":
        continue
    if wants and not any(w in j["name"] for w in wants):
        continue
    print("=====", j["name"][:52])
    for s in j.get("steps", []):
        if s["conclusion"] == "failure":
            print("   STEP:", s["name"])
    log = subprocess.run(
        ["curl", "-sSL", "--max-time", "90", "-H",
         "Authorization: Bearer " + TOKEN,
         API + "/actions/jobs/%s/logs" % j["id"]],
        capture_output=True, text=True).stdout
    lines = [l.split("Z ", 1)[-1] for l in log.splitlines()
             if "##[" not in l and "\x1b[36;1m" not in l]
    lines = [l for l in lines if not any(
        k in l for k in ("Remove container", "github_network", "Post job",
                         "Stop and remove", "Cleaning", "shell:",
                         "git config", "git submodule", "command]"))]
    for l in lines[-14:]:
        print("   ", l[:180])
    print()
