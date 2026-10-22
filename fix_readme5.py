import pathlib

p = pathlib.Path("/tmp/es/README.md")
s = p.read_text()

old = """`components` is a list, so one entry can carry several add-ons. An entry with
components follows its host entry's version when `bump.py` runs: bumping it on
its own would desync the pair."""

new = """## requires: dependencies, with optional version ranges

`requires` names setups that must be installed first. A requirement may pin an
exact setup, name a version line, or give a range — all resolved against what
the manifest actually publishes:

| you write | you get |
|---|---|
| `erlang-29.1.2` | exactly that setup |
| `erlang-29` | that tool, newest 29.x |
| `erlang@>=29 <30` | any 29.x (newest wins) |
| `erlang@>=29,<30` | same, comma-separated |
| `erlang` | newest of that tool |

The `@` separates the tool from the constraint, so `erlang-29` (a version
prefix) and `erlang@>=29` (a range) are never confused.

**A requirement that matches nothing is an error**, naming the published
versions:

```
requires 'erlang@>=99': no erlang satisfies '>=99' (published: 29.1.2, 29.0.1)
```

That matters because a dependency silently resolving to nothing would install
the dependent with no runtime at all, and fail much later and far from the
cause.

`install.sh elixir-1` prints the whole plan; `matrixlib.py plan elixir-1` shows
it with the dependencies marked:

```
erlang-29.1.2  (required)
elixir-1.20.4
```"""

assert old in s, "components paragraph not found"
p.write_text(s.replace(old, new, 1))
print("README updated")
