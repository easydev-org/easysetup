"""cleanup.py — delete the superseded single-version releases.

The first cut published `node-22.20.0`, `python-3.12.15`, `go-1.27.2` and
`java-21.0.8+9` under the old `<tool>-<version>` scheme. The current scheme is
`<id>-<version>` and those four are not referenced by matrix.yml any more, so
they would only confuse anyone browsing Releases.
"""

import json
import os
import urllib.error
import urllib.request

TOKEN = ""
for line in open(os.path.expanduser("~/.config/gh/hosts.yml")):
    if "oauth_token:" in line:
        TOKEN = line.split("oauth_token:")[1].strip()
        break

API = "https://api.github.com/repos/easydev-org/easysetup"

STALE = ["node-22.20.0", "python-3.12.15", "go-1.27.2", "java-21.0.8+9"]


def call(method, path):
    req = urllib.request.Request(API + path, method=method, headers={
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
    })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        return e.code, None


releases = {r["tag_name"]: r["id"] for r in call("GET", "/releases?per_page=100")[1]}

for tag in STALE:
    rid = releases.get(tag)
    if not rid:
        print(f"gone already: {tag}")
        continue
    status, _ = call("DELETE", f"/releases/{rid}")
    print(f"{'deleted' if status == 204 else 'FAILED'} {tag} ({status})")
    # The tag itself is a separate object.
    status, _ = call("DELETE", f"/git/refs/tags/{tag}")
    print(f"  tag {'deleted' if status == 204 else status}")
