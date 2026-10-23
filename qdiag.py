"""Pull one job's log and print the lines diag.sh produced.

GitHub's log stream interleaves the echoed script with its output, so filtering
by the markers diag.sh prints is more reliable than by line position.
"""

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


job = sys.argv[1]
log = subprocess.run(
    ["curl", "-sSL", "--max-time", "90", "-H",
     "Authorization: Bearer " + TOKEN, API + "/actions/jobs/%s/logs" % job],
    capture_output=True, text=True).stdout

lines = [l.split("Z ", 1)[-1] for l in log.splitlines()]
# Strip ANSI colour and the "##[group]" framing.
clean = []
for l in lines:
    for code in ("\x1b[36;1m", "\x1b[0m", "\x1b[32;1m", "\x1b[1m"):
        l = l.replace(code, "")
    clean.append(l.rstrip())

marks = ("== cwd ==", "== setup files", "== git state", "== what nix sees",
         "== can each", "versions ", "packages ", "tracked in setups",
         "FAILED", "error:", "1.8.2", "HEAD", "M ", "?? ")
printing = False
for l in clean:
    if "== cwd ==" in l:
        printing = True
    if printing:
        if l.strip():
            print(l[:190])
