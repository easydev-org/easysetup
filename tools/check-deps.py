#!/usr/bin/env python3
"""check-deps.py — list the shared libraries a built tree needs but that its
apt_deps does not provide.

Why this exists: php failed three CI rounds in a row, each time on a different
missing library (libsodium, then libargon2, ...), because apt_deps was written
from memory. Guessing one library per round is the wrong loop: this walks every
ELF in the tree, reads its DT_NEEDED, maps each to the debian package that ships
it, and reports the ones the entry's apt_deps is missing.

    python3 tools/check-deps.py <tree-dir> <setup-dir> [--map-only]

Run it after a build, before packing, with the tree staged at /tmp/stage.
It reads matrix.yml through matrixlib for the apt_deps list.
"""

import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import matrixlib  # noqa: E402


# soname -> debian package. Only the libraries our toolchains actually pull in;
# anything unmapped is REPORTED rather than silently ignored, so a new one shows
# up instead of slipping through.
SONAME_PKG = {
    "libargon2.so.1": "libargon2-1",
    "libsodium.so.23": "libsodium23",
    "libpcre2-8.so.0": "libpcre2-8-0",
    "libxml2.so.2": "libxml2",
    "libz.so.1": "zlib1g",
    "libssl.so.3": "libssl3",
    "libcrypto.so.3": "libssl3",
    "libgcc_s.so.1": "libgcc-s1",
    "libstdc++.so.6": "libstdc++6",
    "libicuuc.so.76": "libicu76",
    "libicui18n.so.76": "libicu76",
    "libicudata.so.76": "libicu76",
    "libffi.so.8": "libffi8",
    "libyaml-0.so.2": "libyaml-0-2",
    "libgmp.so.10": "libgmp10",
    "libreadline.so.8": "libreadline8",
    "libsqlite3.so.0": "libsqlite3-0",
    "libbz2.so.1.0": "libbz2-1.0",
    "liblzma.so.5": "liblzma5",
    "libonig.so.5": "libonig5",
    "libcurl.so.4": "libcurl4",
    "libncursesw.so.6": "libncursesw6",
    "libtinfo.so.6": "libtinfo6",
    "libatomic.so.1": "libatomic1",
    # Provided by the base system; always present.
    "libc.so.6": None,
    "libm.so.6": None,
    "libpthread.so.0": None,
    "libdl.so.2": None,
    "librt.so.1": None,
    "ld-linux-x86-64.so.2": None,
    "linux-vdso.so.1": None,
}


def dt_needed(path):
    """DT_NEEDED entries of an ELF file (no readelf dependency)."""
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF":
        return []
    is64 = data[4] == 2
    if is64:
        e_shoff, = struct.unpack_from("<Q", data, 0x28)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    else:
        e_shoff, = struct.unpack_from("<I", data, 0x20)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x2E)

    def sec(i):
        off = e_shoff + i * e_shentsize
        if is64:
            name, typ = struct.unpack_from("<II", data, off)
            _addr, offset, size = struct.unpack_from("<QQQ", data, off + 0x10)
            link, = struct.unpack_from("<I", data, off + 0x28)
        else:
            name, typ = struct.unpack_from("<II", data, off)
            _addr, offset, size = struct.unpack_from("<III", data, off + 0x0C)
            link, = struct.unpack_from("<I", data, off + 0x18)
        return name, offset, size, link

    _n, strtab_off, _s, _l = sec(e_shstrndx)
    out = []
    for i in range(e_shnum):
        nameoff, offset, size, link = sec(i)
        nm = data[strtab_off + nameoff:data.index(b"\0", strtab_off + nameoff)].decode()
        if nm != ".dynamic":
            continue
        _dn, dstr_off, _ds, _dl = sec(link)
        step = 16 if is64 else 8
        for k in range(0, size, step):
            if is64:
                tag, val = struct.unpack_from("<qQ", data, offset + k)
            else:
                tag, val = struct.unpack_from("<iI", data, offset + k)
            if tag == 0:
                break
            if tag == 1:
                s = dstr_off + val
                out.append(data[s:data.index(b"\0", s)].decode())
    return out


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    tree, setup = argv[1], argv[2]
    e = matrixlib.by_dir(setup)
    if e is None:
        sys.exit(f"check-deps: no setup '{setup}' in matrix.yml")
    have = set(e.get("apt_deps") or [])

    needed = set()
    for root, _dirs, files in os.walk(tree):
        for f in files:
            p = os.path.join(root, f)
            try:
                for lib in dt_needed(p):
                    needed.add(lib)
            except Exception:
                pass

    missing, unknown = [], []
    for lib in sorted(needed):
        if lib not in SONAME_PKG:
            unknown.append(lib)
            continue
        pkg = SONAME_PKG[lib]
        if pkg and pkg not in have:
            missing.append((lib, pkg))

    if unknown:
        print("unmapped sonames (add them to SONAME_PKG so they are checked):")
        for u in unknown:
            print("  ", u)
    if missing:
        print("MISSING from apt_deps:")
        for lib, pkg in missing:
            print(f"   {lib:24} -> {pkg}")
        return 1
    print(f"check-deps: {setup} declares everything its ELFs need")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
