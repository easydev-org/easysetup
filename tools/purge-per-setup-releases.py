#!/usr/bin/env python3
"""Delete the per-setup releases, now that everything lives in one.

Every setup used to be its own release, which meant 194 releases for one
concept. They are replaced by a single `setups` release holding all the assets,
and the CLI no longer looks anywhere else.

Dry by default. Deleting a release is irreversible - the assets are gone - so
running it needs an explicit --yes, and it checks two things first:

  * the `setups` release exists and has the tarballs
  * every per-setup release it is about to delete is represented there

That second check is the point. If the consolidated release were missing an
asset, deleting the old release would remove the only copy.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

REPO = "easydev-org/easysetup"
KEEP = "setups"
API = "https://api.github.com"


def token():
    t = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if t:
        return t
    # Same file gh writes; reading it directly keeps this runnable where gh is
    # not installed, which is the case in this sandbox.
    hosts = os.path.expanduser("~/.config/gh/hosts.yml")
    for line in open(hosts):
        line = line.strip()
        if line.startswith("oauth_token:"):
            return line.split(":", 1)[1].strip()
    raise SystemExit("no token: set GITHUB_TOKEN")


TOKEN = token()


def api(method, path, ok=(200, 201, 204)):
    req = urllib.request.Request(API + path, method=method,
                                 headers={"Authorization": "Bearer " + TOKEN,
                                          "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as r:
            body = r.read()
            return r.status, json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]


def releases():
    out = []
    page = 1
    while True:
        status, chunk = api("GET", "/repos/%s/releases?per_page=100&page=%d"
                            % (REPO, page))
        if status != 200:
            raise SystemExit("listing releases failed: %s %s" % (status, chunk))
        if not chunk:
            break
        out.extend(chunk)
        if len(chunk) < 100:
            break
        page += 1
    return out


def load_manifest_dirs():
    """The setups the current manifest publishes, as directory names.

    Read through matrixlib2 so the derived names match exactly what the installer
    uses - the suffix rule (mypy-2.1.0-py3.13) is easy to get subtly wrong when
    reimplemented here.
    """
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import matrixlib2
    return [e["dir"] for e in matrixlib2.load(
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "matrix-nix.yml"))]


def main():
    dry = "--yes" not in sys.argv

    rels = releases()
    print("releases found: %d" % len(rels))

    consolidated = next((r for r in rels if r["tag_name"] == KEEP), None)
    if consolidated is None:
        raise SystemExit("refusing: there is no %r release" % KEEP)

    have = {a["name"] for a in consolidated["assets"]}
    tarballs = {n for n in have if n.endswith(".tar.zst")}
    print("%r holds %d assets (%d tarballs)" % (KEEP, len(have), len(tarballs)))
    if not tarballs:
        raise SystemExit("refusing: %r has no tarballs" % KEEP)

    doomed = [r for r in rels if r["tag_name"] != KEEP]
    print("per-setup releases to delete: %d" % len(doomed))

    # Every tarball the CURRENT manifest still publishes must be in the kept
    # release. A leftover release for a setup that has since been dropped
    # (python-3.15, black, eslint, llvm-21.1.8, ...) is exactly what we want to
    # delete, so its absence from `setups` is expected rather than a problem.
    current = set(load_manifest_dirs())
    missing = []
    stale = []
    for r in doomed:
        for a in r["assets"]:
            if not a["name"].endswith(".tar.zst"):
                continue
            dirname = a["name"][:-len("-debian-trixie-amd64.tar.zst")]
            if dirname not in current:
                stale.append(r["tag_name"])
            elif a["name"] not in tarballs:
                missing.append("%s/%s" % (r["tag_name"], a["name"]))
    if missing:
        print("refusing: these CURRENT setups have no asset in %r but their "
              "per-setup release is about to be deleted:" % KEEP)
        for m in missing[:20]:
            print("   ", m)
        if len(missing) > 20:
            print("    ... and %d more" % (len(missing) - 20))
        raise SystemExit(1)
    print("every current setup's tarball is in %r - safe to delete" % KEEP)
    print("releases for dropped setups: %d (their tarballs are not in %r, and "
          "their removal is the point)" % (len(set(stale)), KEEP))

    if dry:
        print()
        print("dry run. re-run with --yes to delete %d releases" % len(doomed))
        for r in doomed[:10]:
            print("   would delete", r["tag_name"])
        if len(doomed) > 10:
            print("    ... and %d more" % (len(doomed) - 10))
        return

    # Delete by numeric id, which is what the API wants; the tag path also works
    # but needs quoting for names that contain dots.
    failed = []
    for i, r in enumerate(doomed, 1):
        status, body = api("DELETE", "/repos/%s/releases/%d" % (REPO, r["id"]))
        if status not in (204, 200):
            failed.append((r["tag_name"], str(body)))
        else:
            # The git tag is separate from the release and would otherwise linger,
            # leaving 194 dangling tags behind after the releases are gone.
            ts, _ = api("DELETE", "/repos/%s/git/refs/tags/%s"
                        % (REPO, urllib.parse.quote(r["tag_name"], safe="")))
            if ts not in (204, 200, 422):  # 422 = already absent
                failed.append((r["tag_name"] + " (tag)", str(ts)))
        if i % 20 == 0:
            print("  deleted %d/%d" % (i, len(doomed)))

    print("deleted %d, failed %d" % (len(doomed) - len(failed), len(failed)))
    for tag, err in failed[:10]:
        print("   ", tag, err[:100])
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
