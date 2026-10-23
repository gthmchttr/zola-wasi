#!/usr/bin/env bash
# Regenerate a release's patch series from the commits on ./zola's `wasi` branch.
# Workflow: ZOLA_VERSION=... scripts/setup.sh, edit and commit in ./zola, run this, commit patches/.
#
# Writes to the series that release already uses (patches/<tag>/ or patches/<vMAJOR.MINOR>/), or
# to patches/<vMAJOR.MINOR>/ for a release without one. --exact writes patches/<tag>/ instead,
# for a release that needs different patches from the rest of its line.
#
# Patches are shared, not copied: a commit whose change is identical (same `git patch-id`) to a
# patch any other series already has is listed by that patch's path instead of being written
# again. Patch files are named after their commit subject; the series file holds the order.
. "$(dirname "$0")/common.sh"

[ -d "$ZOLA_DIR/.git" ] || die "no checkout in $ZOLA_DIR: run scripts/setup.sh first"
[ -z "$(git -C "$ZOLA_DIR" status --porcelain)" ] || die "$ZOLA_DIR has uncommitted changes"
checkout="$(git -C "$ZOLA_DIR" config --get zola-wasi.tag || true)"
[ "$checkout" = "$ZOLA_TAG" ] || die "./zola is a $checkout checkout: run with ZOLA_VERSION=$checkout"

line="$(echo "$ZOLA_TAG" | cut -d. -f1-2)"
if [ "${1:-}" = "--exact" ]; then
  target="$ROOT/patches/$ZOLA_TAG"
elif [ -f "$ROOT/patches/$ZOLA_TAG/series" ]; then
  target="$ROOT/patches/$ZOLA_TAG"
else
  target="$ROOT/patches/$line"
fi
rel_target="${target#"$ROOT"/patches/}"
mkdir -p "$target"

patch_id() { git -C "$ZOLA_DIR" patch-id --stable <"$1" | cut -d' ' -f1; }

# patch-id → path (relative to patches/) of every patch outside the target directory
known="$(mktemp)"
work="$(mktemp -d)"
trap 'rm -rf "$known" "$work"' EXIT
find "$ROOT/patches" -name '*.patch' -not -path "$target/*" | sort | while read -r file; do
  echo "$(patch_id "$file") ${file#"$ROOT"/patches/}"
done >"$known"

# Patch files in the target directory that other series use: rewriting them changes those too
used_elsewhere() {
  grep -lx "$rel_target/$1" "$ROOT"/patches/*/series 2>/dev/null | grep -v "^$target/series$" || true
}

series=()
written=()
for commit in $(git -C "$ZOLA_DIR" rev-list --reverse "$ZOLA_TAG..wasi"); do
  file="$(git -C "$ZOLA_DIR" format-patch --no-signature --zero-commit --no-numbered \
    -1 "$commit" --output-directory "$work")"
  name="${file##*/}"
  name="${name#[0-9][0-9][0-9][0-9]-}"
  shared="$(awk -v id="$(patch_id "$file")" '$1 == id {print $2; exit}' "$known")"
  if [ -n "$shared" ]; then
    log "Sharing $shared"
    series+=("$shared")
  else
    if [ -f "$target/$name" ] && ! cmp -s "$file" "$target/$name" && [ -n "$(used_elsewhere "$name")" ]; then
      log "Warning: $rel_target/$name changed, and is also used by: $(used_elsewhere "$name" | xargs -n1 dirname | xargs -n1 basename | xargs)"
    fi
    mv "$file" "$target/$name"
    series+=("$rel_target/$name")
    written+=("$name")
  fi
  rm -f "$file"
done

{
  echo "# Patches for Zola $( [ "$rel_target" = "$line" ] && echo "$line.x" || echo "$ZOLA_TAG"), applied in this order."
  echo "# Paths are relative to patches/; entries from other directories are shared with those versions."
  printf '%s\n' ${series[@]+"${series[@]}"}
} >"$target/series"

# Drop patch files that no series uses any more
for file in "$target"/*.patch; do
  [ -e "$file" ] || continue
  name="${file##*/}"
  if ! grep -qx "$rel_target/$name" "$ROOT"/patches/*/series; then
    log "Removing unused $rel_target/$name"
    rm "$file"
  fi
done

# Every series must still resolve
for other in "$ROOT"/patches/*/series; do
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$other" | while read -r entry; do
    [ -f "$ROOT/patches/$entry" ] || die "${other#"$ROOT"/}: $entry is missing"
  done
done
log "Exported ${#series[@]} patch(es) to patches/$rel_target/series (${#written[@]} written, $((${#series[@]} - ${#written[@]})) shared)"
