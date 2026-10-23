#!/usr/bin/env bash
# Add a Zola release to VERSIONS, the list of versions zola-wasi releases, making it the default.
#
#   scripts/update-upstream.sh            # the latest release on GitHub
#   scripts/update-upstream.sh v0.24.0    # a specific tag
#
# Every version stays listed, since each one gets (or has) a release. A patch release (v0.23.7)
# uses its line's existing series; a new line (v0.24.0) with no patches yet starts with a series
# that reuses the previous line's patches. Check with scripts/setup.sh whether they still apply.
#
# Prints the tag. Exits 0 when files changed, 3 when the release is already listed.
. "$(dirname "$0")/common.sh"

tag="${1:-}"
if [ -z "$tag" ]; then
  api="https://api.github.com/repos/getzola/zola/releases/latest"
  auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  tag="$(curl --fail --silent --show-error ${auth[@]+"${auth[@]}"} "$api" | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')"
fi
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected Zola tag: $tag"

if zola_versions | awk '{print $1}' | grep -qx "$tag"; then
  log "$tag is already in VERSIONS"
  echo "$tag"
  exit 3
fi

# The commit the tag points at (peeled, for annotated tags)
commit="$(git ls-remote "$ZOLA_REPO" "refs/tags/$tag^{}" "refs/tags/$tag" | awk 'NR == 1 {print $1}')"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "couldn't resolve $tag in $ZOLA_REPO"

line="$(echo "$tag" | cut -d. -f1-2)"
python3 - "$ROOT/VERSIONS" "$tag" "$commit" "$line" <<'EOF'
import sys
path, tag, commit, line = sys.argv[1:]
kept = open(path).read().splitlines()
kept.append(f"{tag} {commit}")
# Oldest first: sort the entries by version, keeping the comment header in place
header = [l for l in kept if not l.split("#")[0].strip()]
entries = sorted((l for l in kept if l.split("#")[0].strip()),
                 key=lambda l: tuple(int(n) for n in l.split()[0][1:].split(".")))
open(path, "w").write("\n".join(header + entries) + "\n")
EOF

if [ ! -f "$ROOT/patches/$tag/series" ] && [ ! -f "$ROOT/patches/$line/series" ]; then
  # The closest older release (VERSIONS is sorted), or the oldest one if this release predates them all
  previous="$(zola_versions | awk -v tag="$tag" '$1 == tag {print prev; exit} {prev = $1}')"
  [ -n "$previous" ] || previous="$(zola_versions | awk '{print $1}' | grep -vx "$tag" | head -n 1)"
  [ -n "$previous" ] || die "no earlier release to take patches from"
  from="$(series_dir "$previous")"
  mkdir -p "$ROOT/patches/$line"
  {
    echo "# Patches for Zola $line.x, applied in this order."
    echo "# Started as ${from#"$ROOT"/patches/}'s series: entries that don't apply to $line need $line versions"
    echo "# (scripts/setup.sh, fix in ./zola, scripts/export-patches.sh)."
    sed -e '/^#/d' -e '/^[[:space:]]*$/d' "$from/series"
  } >"$ROOT/patches/$line/series"
  log "Created patches/$line/series from ${from#"$ROOT"/patches/}'s patches"
fi

log "Added $tag ($commit) to VERSIONS"
echo "$tag"
