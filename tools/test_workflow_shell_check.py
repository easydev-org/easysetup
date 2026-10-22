#!/usr/bin/env python3
"""The workflow shell checker must CATCH expressions that break when they are empty.

The real trap, and the one this guards:

    for req in ${{ matrix.requires }}; do

`matrix.requires` holds "swift@>=6.4 <7". Rendered inline, that puts a bare `>`
and `<` into the script and bash dies with "syntax error near unexpected token
`>`" - which is exactly what failed three Swift SDK builds at verify time, after
their artifacts had been produced correctly.

A checker that substitutes a shell-SAFE placeholder ("GH_EXPR") cannot see it.
That is why the substitution here must contain metacharacters, and this test
asserts precisely that difference.
"""

import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import re


def bash_ok(script):
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as t:
        t.write(script)
        p = t.name
    r = subprocess.run(["bash", "-n", p], capture_output=True)
    pathlib.Path(p).unlink()
    return r.returncode == 0


# The shape that actually broke: a range constraint inlined into a for-list.
BROKEN = 'for req in ${{ matrix.requires }}; do\n  echo "$req"\ndone\n'

fail = 0


def check(name, cond):
    global fail
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fail = 1


# A shell-safe placeholder hides it completely...
check("a safe placeholder hides the bug",
      bash_ok(re.sub(r"\$\{\{[^}]*\}\}", "GH_EXPR", BROKEN)))
# ...a metacharacter-bearing substitution exposes it.
check("a metacharacter substitution exposes the bug",
      not bash_ok(re.sub(r"\$\{\{[^}]*\}\}", "X>Y <Z", BROKEN)))
# The fixed form (list via env:, referenced unquoted) survives.
FIXED = 'for req in ${REQS:-}; do\n  echo "$req"\ndone\n'
check("the fixed form is valid bash", bash_ok(FIXED))

print(f"\ntest_workflow_shell_check: {'FAILED' if fail else 'ok'}")
raise SystemExit(1 if fail else 0)
