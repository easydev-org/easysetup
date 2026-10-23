"""Break down the setup count: entries, distinct tools, and which have versions."""

import sys
from collections import Counter

sys.path.insert(0, "/data/es")
import matrixlib2

es = matrixlib2.load("/data/es/matrix-nix.yml")
c = Counter(e["tool"] for e in es)

print("条目（每个都是一个 tarball）: %d" % len(es))
print("不同工具                   : %d" % len(c))
print()
print("有多个版本的工具:")
for t, n in sorted(c.items(), key=lambda x: (-x[1], x[0])):
    if n > 1:
        vs = [e["version"] for e in es if e["tool"] == t]
        print("  %-10s %d 个版本: %s" % (t, n, ", ".join(vs)))
print()
single = sorted(t for t, n in c.items() if n == 1)
print("只有一个版本的工具: %d 个" % len(single))
print("  " + ", ".join(single))
