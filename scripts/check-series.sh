#!/usr/bin/env bash
# Quick consistency check, no network: every release in VERSIONS has a patch series, every series
# entry exists, and every patch file is used by some series.
. "$(dirname "$0")/common.sh"

status=0
while read -r tag _; do
  if ! files="$(patch_files "$tag")"; then
    status=1
    continue
  fi
  echo "$tag: $(echo "$files" | grep -c .) patch(es) from $(series_dir "$tag" | sed "s#$ROOT/##")/series"
done < <(zola_versions)

used="$(cat "$ROOT"/patches/*/series | sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' | sort -u)"
while read -r file; do
  rel="${file#"$ROOT"/patches/}"
  if ! grep -qx "$rel" <<<"$used"; then
    printf '\033[1;31merror:\033[0m patches/%s is not in any series\n' "$rel" >&2
    status=1
  fi
done < <(find "$ROOT/patches" -name '*.patch' | sort)

exit "$status"
