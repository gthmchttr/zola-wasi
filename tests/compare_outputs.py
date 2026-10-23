#!/usr/bin/env python3
"""Compare two Zola output directories, e.g. a native build and a wasm build of the same site.

usage: compare_outputs.py EXPECTED_DIR ACTUAL_DIR [EXPECTED_AGAIN_DIR...]
       compare_outputs.py --unstable EXPECTED_DIR EXPECTED_AGAIN_DIR...

Exits non-zero when they differ. EXPECTED_AGAIN_DIRs, more builds made the same way as
EXPECTED_DIR, identify files the build itself doesn't produce deterministically (some Zola
releases order unsorted pages differently on every run): those are reported and skipped.
--unstable just prints those files' paths, one per line.

Two differences are expected between a 64-bit native build and a 32-bit wasm build and are
normalised away:

- Processed image file names: Zola names them by a hash of the resize operation, and that hash
  depends on the pointer width. The 16-hex-digit hash is replaced by HASH in paths and contents.
- Processed image bytes: the encoders take different SIMD paths, so pixels can differ slightly.
  Images under processed_images/ are compared by name only.
"""
import hashlib
import os
import re
import sys

IMAGE_HASH = re.compile(rb"\.[0-9a-f]{16}\.(png|jpe?g|webp|avif|gif)")


def snapshot(root):
    files = {}
    for dirpath, _, names in os.walk(root):
        for name in names:
            path = os.path.join(dirpath, name)
            rel = IMAGE_HASH.sub(rb".HASH.\1", os.path.relpath(path, root).encode()).decode()
            if rel.startswith("processed_images/"):
                files[rel] = None
                continue
            with open(path, "rb") as f:
                files[rel] = hashlib.sha256(IMAGE_HASH.sub(rb".HASH.\1", f.read())).hexdigest()
    return files


def unstable_files(expected, others):
    unstable = set()
    for again in others:
        unstable |= {k for k in expected.keys() | again.keys() if expected.get(k) != again.get(k)}
    return unstable


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "--unstable":
        builds = [snapshot(d) for d in sys.argv[2:]]
        print("\n".join(sorted(unstable_files(builds[0], builds[1:]))))
        return
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    expected, actual = snapshot(sys.argv[1]), snapshot(sys.argv[2])
    unstable = unstable_files(expected, [snapshot(d) for d in sys.argv[3:]])
    if unstable:
        for item in sorted(unstable):
            print(f"  skipped, not deterministic upstream: {item}")
        expected = {k: v for k, v in expected.items() if k not in unstable}
        actual = {k: v for k, v in actual.items() if k not in unstable}
    missing = sorted(expected.keys() - actual.keys())
    extra = sorted(actual.keys() - expected.keys())
    changed = sorted(k for k in expected.keys() & actual.keys() if expected[k] != actual[k])
    for label, items in (("missing", missing), ("unexpected", extra), ("different", changed)):
        for item in items[:20]:
            print(f"  {label}: {item}")
        if len(items) > 20:
            print(f"  ... and {len(items) - 20} more {label}")
    if missing or extra or changed:
        sys.exit(f"outputs differ ({len(missing)} missing, {len(extra)} unexpected, {len(changed)} different)")
    print(f"  {len(expected)} files match" + (f" ({len(unstable)} skipped)" if unstable else ""))


if __name__ == "__main__":
    main()
