#!/usr/bin/env bash
# Point UPSTREAM (and web/package.json's version) at a Zola release.
#
#   scripts/update-upstream.sh            # the latest release on GitHub
#   scripts/update-upstream.sh v0.24.0    # a specific tag
#
# Prints the tag it settled on. Exits 0 when files changed, 3 when already up to date.
. "$(dirname "$0")/common.sh"

tag="${1:-}"
if [ -z "$tag" ]; then
  api="https://api.github.com/repos/getzola/zola/releases/latest"
  auth=()
  [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  tag="$(curl --fail --silent --show-error ${auth[@]+"${auth[@]}"} "$api" | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')"
fi
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected Zola tag: $tag"

if [ "$tag" = "$ZOLA_TAG" ]; then
  log "Already on $tag"
  echo "$tag"
  exit 3
fi

# The commit the tag points at (peeled, for annotated tags)
commit="$(git ls-remote "$ZOLA_REPO" "refs/tags/$tag^{}" "refs/tags/$tag" | awk 'NR == 1 {print $1}')"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "couldn't resolve $tag in $ZOLA_REPO"

python3 - "$ROOT" "$tag" "$commit" <<'EOF'
import json, pathlib, re, sys
root, tag, commit = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]

upstream = root / "UPSTREAM"
text = upstream.read_text()
text = re.sub(r"(?m)^ZOLA_TAG=.*$", f"ZOLA_TAG={tag}", text)
text = re.sub(r"(?m)^ZOLA_COMMIT=.*$", f"ZOLA_COMMIT={commit}", text)
upstream.write_text(text)

package = root / "web" / "package.json"
data = json.loads(package.read_text())
data["version"] = tag.removeprefix("v")
package.write_text(json.dumps(data, indent=2) + "\n")
EOF

log "Updated UPSTREAM: $ZOLA_TAG → $tag ($commit)"
echo "$tag"
