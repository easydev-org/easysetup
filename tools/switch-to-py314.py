#!/usr/bin/env python3
"""Move every python-package setup from 3.15 to 3.14.

Measured at our own flake.lock revision (which IS nixos-unstable's channel
revision, so pinning an older unstable is not an option):

  python311Packages.pip   404
  python312Packages.pip   200
  python313Packages.pip   200
  python314Packages.pip   200
  python315Packages.pip   404

Hydra builds the package set for some interpreters and not others. 3.15 is the
newest, and its package set is not built; 3.14 is and is only one minor behind.
Choosing 314 means every one of our python setups substitutes from the cache
instead of compiling, which is the difference between ~40 minutes and ~2.
"""

import pathlib

p = pathlib.Path("/data/es/matrix-nix.yml")
s = p.read_text()

before = s
s = s.replace("nixpkgs#python315Packages.", "nixpkgs#python314Packages.")
s = s.replace('nixpkgs#python315"', 'nixpkgs#python314"')
s = s.replace('version: "3.15.0" }', 'version: "3.14.8" }')
s = s.replace(
    "compute-deps.py derives that pip's closure contains python315's, so pip's",
    "compute-deps.py derives that pip's closure contains python314's, so pip's",
)

if s == before:
    raise SystemExit("nothing changed - the pattern did not match")
p.write_text(s)
print("switched to python 3.14")
