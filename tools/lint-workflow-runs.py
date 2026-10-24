#!/usr/bin/env python3
"""Syntax-check every `run:` block in the workflows, not just the YAML.

A workflow can be valid YAML and still have broken shell in it - a stray `done`
or an unclosed quote is invisible to a yaml parser and only shows up when
Actions runs it. This extracts each `run:` body and runs `bash -n` on it.

    tools/lint-workflow-runs.py
"""

import glob
import os
import subprocess
import sys
import tempfile

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    bad = 0
    for wf in sorted(glob.glob(os.path.join(ROOT, ".github/workflows/*.yml"))):
        try:
            doc = yaml.safe_load(open(wf))
        except Exception as e:
            print("%-34s YAML INVALID: %s" % (os.path.basename(wf), str(e)[:80]))
            bad += 1
            continue
        for job, jd in (doc.get("jobs") or {}).items():
            for st in (jd.get("steps") or []):
                body = st.get("run")
                if not body:
                    continue
                label = "%s/%s" % (os.path.basename(wf), st.get("name", "?")[:30])
                with tempfile.NamedTemporaryFile("w", suffix=".sh",
                                                 delete=False) as f:
                    f.write(body)
                    path = f.name
                rc = subprocess.run(["bash", "-n", path],
                                    capture_output=True, text=True)
                os.unlink(path)
                if rc.returncode != 0:
                    print("%-46s SHELL INVALID: %s"
                          % (label, rc.stderr.strip().splitlines()[-1][:70]))
                    bad += 1
    if bad:
        print("\n%d problem(s)" % bad)
        return 1
    print("all workflows parse and every run: block is valid shell")
    return 0


if __name__ == "__main__":
    sys.exit(main())
