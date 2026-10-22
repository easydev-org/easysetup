#!/usr/bin/env python3
"""Check that every `run:` script embedded in the workflows is valid bash.

A syntax error inside a `run: |` block is invisible until the job executes it -
which is how a broken `case` arm in the verify step survived a YAML parse and
then failed all three Swift SDK builds at verification time, after their
artifacts had already been built correctly.

GitHub expressions (${{ ... }}) are replaced with a placeholder so the shell
sees valid syntax.
"""

import pathlib
import re
import subprocess
import sys
import tempfile

import yaml


def indent_of(line):
    return len(line) - len(line.lstrip())


def scripts_from(text):
    """Yield (name, script) for each `run:` in a workflow, via yaml where possible."""
    doc = yaml.safe_load(text)
    out = []

    def walk(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                if k == "run" and isinstance(v, str):
                    out.append((path, v))
                else:
                    walk(v, path + "/" + str(k))
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, path + "/" + str(i))

    walk(doc, "")
    return out


def main():
    files = sorted(pathlib.Path(".github/workflows").glob("*.yml"))
    bad = 0
    checked = 0
    for f in files:
        for name, script in scripts_from(f.read_text()):
            # A composite action's `run:` has no shell of its own; workflows do.
            s = re.sub(r"\$\{\{[^}]*\}\}", "GH_EXPR", script)
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as t:
                t.write(s)
                tmp = t.name
            r = subprocess.run(["bash", "-n", tmp], capture_output=True, text=True)
            checked += 1
            if r.returncode != 0:
                print("FAIL %s%s" % (f, name))
                print("     " + r.stderr.strip().replace("\n", "\n     ")[:400])
                bad += 1
            pathlib.Path(tmp).unlink()
    if not bad:
        print("ok   %d run: script(s) parse as bash" % checked)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
