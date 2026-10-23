#!/usr/bin/env python3
"""Compare two Zola output directories, e.g. a native build and a wasm build of the same site.

usage: compare_outputs.py EXPECTED_DIR ACTUAL_DIR

Exits non-zero when they differ. Two differences are expected between a 64-bit native build and
a 32-bit wasm build and are normalised away:

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


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    expected, actual = snapshot(sys.argv[1]), snapshot(sys.argv[2])
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
    print(f"  {len(expected)} files match")


if __name__ == "__main__":
    main()
