import json
import os
import subprocess
import sys

TOKEN = ""
for line in open(os.path.expanduser("~/.config/gh/hosts.yml")):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

RID = sys.argv[1]
API = "https://api.github.com/repos/easydev-org/easysetup"


def gh(p):
    return subprocess.run(
        ["curl", "-sSL", "--max-time", "90",
         "-H", "Authorization: Bearer " + TOKEN, API + p],
        capture_output=True, text=True).stdout


wanted = sys.argv[2:]
for j in json.loads(gh("/actions/runs/%s/jobs?per_page=10" % RID))["jobs"]:
    if wanted and not any(w in j["name"] for w in wanted):
        continue
    print("=====", j["name"][:30], "[%s]" % j["conclusion"])
    if j["conclusion"] != "failure":
        continue
    for s in j.get("steps", []):
        if s["conclusion"] == "failure":
            print("   STEP:", s["name"])
    log = gh("/actions/jobs/%s/logs" % j["id"])
    lines = [l.split("Z ", 1)[-1] for l in log.splitlines()
             if "##[" not in l and "\x1b[36;1m" not in l]
    for l in lines[-14:]:
        print("   ", l[:180])
    print()
