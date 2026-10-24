#!/usr/bin/env python3
"""Print one action.yml step's run: block, so it can be exercised directly.

    tools/extract-step.py "prepare /nix/store" > /tmp/prep.sh

Used to run the action's shell outside Actions - the same script, not a copy of
it, because a copy would drift.
"""

import sys

import yaml

doc = yaml.safe_load(open("action.yml"))
want = sys.argv[1]
for s in doc["runs"]["steps"]:
    if s.get("name") == want:
        sys.stdout.write(s["run"])
        break
else:
    sys.exit("no step named %r" % want)
