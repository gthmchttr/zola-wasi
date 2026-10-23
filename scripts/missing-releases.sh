#!/usr/bin/env bash
# Print the Zola releases in VERSIONS that have no GitHub release yet, oldest first, one per line.
# A version counts as released if a release is tagged with it (v0.23.6) or re-released with a
# suffix (v0.23.6-2). Needs the GitHub CLI (`gh`), authenticated for this repository.
. "$(dirname "$0")/common.sh"

command -v gh >/dev/null || die "the GitHub CLI (gh) is needed to list releases"
released="$(gh release list --limit 1000 --json tagName --jq '.[].tagName')"

zola_versions | awk '{print $1}' | while read -r tag; do
  if ! grep -qE "^${tag//./\\.}(-[0-9]+)?$" <<<"$released"; then
    echo "$tag"
  fi
done
