#!/usr/bin/env bash
# Regenerate patches/ from the commits on ./zola's `wasi` branch on top of the pinned release.
# Workflow: edit and commit in ./zola, then run this and commit patches/ here.
. "$(dirname "$0")/common.sh"

[ -d "$ZOLA_DIR/.git" ] || die "no checkout in $ZOLA_DIR: run scripts/setup.sh first"
[ -z "$(git -C "$ZOLA_DIR" status --porcelain)" ] || die "$ZOLA_DIR has uncommitted changes"

rm -f "$ROOT"/patches/*.patch
git -C "$ZOLA_DIR" format-patch --quiet --no-signature --zero-commit --no-numbered \
  --output-directory "$ROOT/patches" "$ZOLA_TAG..wasi"
log "Exported $(find "$ROOT/patches" -name '*.patch' | wc -l | tr -d ' ') patch(es) to patches/"
