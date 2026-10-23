#!/usr/bin/env python3
"""Query search.nixos.org's backend directly.

The website needs javascript, but the search endpoint behind it is a plain POST.
This uses it so attribute names come from the index nixpkgs publishes rather than
from guessing.

    tools/nixsearch.py <query> [size]
"""

import json
import subprocess
import sys

ENDPOINT = "https://search.nixos.org/backend/latest-52-nixos-unstable/_search"


def search(query, size=8):
    body = {
        "from": 0,
        "size": size,
        "_source": ["type", "package_attr_name", "package_pname",
                    "package_description", "package_pversion"],
        "query": {
            "bool": {
                "filter": [{"term": {"type": "package"}}],
                "must": [{
                    "multi_match": {
                        "query": query,
                        "type": "best_fields",
                        "operator": "and",
                        "fields": ["package_attr_name.edge^4",
                                   "package_pname.edge^3",
                                   "package_description.edge^0.5"],
                    }
                }],
            }
        },
    }
    out = subprocess.run(
        ["curl", "-sS", "--max-time", "60", "-X", "POST", ENDPOINT,
         "-H", "Content-Type: application/json", "-d", json.dumps(body)],
        capture_output=True, text=True).stdout
    try:
        return json.loads(out)["hits"]["hits"]
    except Exception:
        sys.exit("search failed: %s" % out[:300])


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    q = argv[1]
    n = int(argv[2]) if len(argv) > 2 else 8
    for h in search(q, n):
        s = h["_source"]
        print("%-40s %-14s %s" % (
            s.get("package_attr_name", "?"),
            s.get("package_pversion", ""),
            (s.get("package_description") or "")[:60]))


if __name__ == "__main__":
    main(sys.argv)
