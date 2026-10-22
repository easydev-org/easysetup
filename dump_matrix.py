import yaml

d = yaml.safe_load(open("matrix.yml"))
if isinstance(d, dict):
    for k in ("setups", "entries", "matrix", "tools"):
        if k in d:
            d = d[k]
            break
rows = d if isinstance(d, list) else []
print("entries:", len(rows))

want = {
    "node", "python", "go", "java", "maven", "gradle", "ruby", "rust", "php",
    "perl", "dotnet", "elixir", "erlang", "dart", "deno", "julia", "helm",
    "bazel", "conda", "sbt", "swift", "buf", "r", "lua", "luarocks", "opam",
    "ghc", "cabal", "cmake", "git-lfs", "nim", "zig", "crystal",
}
seen = {}
for r in rows:
    if not isinstance(r, dict):
        continue
    t = r.get("tool")
    if t in want:
        seen.setdefault(t, []).append(r.get("version"))

for t in sorted(seen):
    print("  %-10s %s" % (t, ", ".join(str(v) for v in seen[t])))
print()
print("NOT published (used by the easyblobs CI today):")
for t in ("nix", "conan", "jenkins-plugin-cli"):
    if t not in seen:
        print("  " + t)
