#!/usr/bin/env bash
# Check out the pinned Zola release into ./zola and apply patches/ on top, as commits on the `wasi` branch.
# Safe to re-run: an existing checkout is reset to the release and the patches are applied again.
# Pass --keep to leave an existing checkout alone (e.g. while you're editing it).
. "$(dirname "$0")/common.sh"

if [ "${1:-}" = "--keep" ] && [ -d "$ZOLA_DIR/.git" ]; then
  log "Keeping existing checkout in $ZOLA_DIR"
  exit 0
fi

if [ ! -d "$ZOLA_DIR/.git" ]; then
  log "Cloning $ZOLA_REPO at $ZOLA_TAG"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$ZOLA_TAG" "$ZOLA_REPO" "$ZOLA_DIR"
elif [ -n "$(git -C "$ZOLA_DIR" status --porcelain)" ]; then
  die "$ZOLA_DIR has uncommitted changes; commit them and run scripts/export-patches.sh, or discard them first"
fi

git -C "$ZOLA_DIR" fetch --quiet --depth 1 origin "refs/tags/$ZOLA_TAG:refs/tags/$ZOLA_TAG" 2>/dev/null || true
actual="$(git -C "$ZOLA_DIR" rev-parse "$ZOLA_TAG^{commit}")"
[ "$actual" = "$ZOLA_COMMIT" ] || die "$ZOLA_TAG is $actual, expected $ZOLA_COMMIT (tag moved?)"

git -C "$ZOLA_DIR" checkout --quiet -B wasi "$ZOLA_TAG"
shopt -s nullglob
patches=("$ROOT"/patches/*.patch)
if [ ${#patches[@]} -gt 0 ]; then
  log "Applying ${#patches[@]} patch(es)"
  git -C "$ZOLA_DIR" -c user.name=zola-wasi -c user.email=zola-wasi@localhost \
    am --quiet --committer-date-is-author-date "${patches[@]}"
fi
log "Zola $ZOLA_TAG + patches ready in $ZOLA_DIR (branch wasi)"
