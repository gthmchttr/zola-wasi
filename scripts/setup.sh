#!/usr/bin/env bash
# Check out a Zola release into ./zola and apply its patch series on top, as commits on the
# `wasi` branch. The release is ZOLA_VERSION, or the newest in VERSIONS.
#
# Re-running resets the checkout to the release and applies the patches again; switching
# ZOLA_VERSION reuses the same checkout (and its Cargo build cache).
# --keep leaves the checkout alone if it's already for this release, e.g. while you edit it.
. "$(dirname "$0")/common.sh"

checkout_tag() { git -C "$ZOLA_DIR" config --get zola-wasi.tag 2>/dev/null || true; }

if [ "${1:-}" = "--keep" ] && [ -d "$ZOLA_DIR/.git" ] && [ "$(checkout_tag)" = "$ZOLA_TAG" ]; then
  log "Keeping existing $ZOLA_TAG checkout in $ZOLA_DIR"
  exit 0
fi

if [ ! -d "$ZOLA_DIR/.git" ]; then
  log "Cloning $ZOLA_REPO at $ZOLA_TAG"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$ZOLA_TAG" "$ZOLA_REPO" "$ZOLA_DIR"
else
  if [ -n "$(git -C "$ZOLA_DIR" status --porcelain)" ]; then
    die "$ZOLA_DIR has uncommitted changes; commit them and run scripts/export-patches.sh, or discard them first"
  fi
  previous="$(checkout_tag)"
  [ "$previous" = "$ZOLA_TAG" ] || log "Switching the checkout from ${previous:-unknown} to $ZOLA_TAG"
  git -C "$ZOLA_DIR" fetch --quiet --depth 1 origin "refs/tags/$ZOLA_TAG:refs/tags/$ZOLA_TAG"
fi

actual="$(git -C "$ZOLA_DIR" rev-parse "$ZOLA_TAG^{commit}")"
[ "$actual" = "$ZOLA_COMMIT" ] || die "$ZOLA_TAG is $actual, expected $ZOLA_COMMIT (tag moved?)"

git -C "$ZOLA_DIR" checkout --quiet -B wasi "$ZOLA_TAG"
git -C "$ZOLA_DIR" config zola-wasi.tag "$ZOLA_TAG"

patches=()
while IFS= read -r patch; do patches+=("$patch"); done < <(patch_files "$ZOLA_TAG")
series="$(series_dir "$ZOLA_TAG")"
log "Applying ${#patches[@]} patch(es) from ${series#"$ROOT"/}/series"
if [ ${#patches[@]} -gt 0 ]; then
  git -C "$ZOLA_DIR" -c user.name=zola-wasi -c user.email=zola-wasi@localhost \
    am --quiet --committer-date-is-author-date "${patches[@]}"
fi
log "Zola $ZOLA_TAG + patches ready in $ZOLA_DIR (branch wasi)"
