#!/usr/bin/env bash
# Assemble release assets from dist/zola.wasm (run scripts/build.sh first) into dist/release/:
#
#   zola.wasm                  Zola's CLI for wasm32-wasip1
#   zola.wasm.gz               the same, gzipped
#   zola-wasi-<version>.tgz    the JavaScript package (npm install ./zola-wasi-<version>.tgz), zola.wasm included
#   SHA256SUMS
. "$(dirname "$0")/common.sh"

[ -f "$DIST_DIR/zola.wasm" ] || die "dist/zola.wasm missing: run scripts/build.sh first"
version="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/web/package.json")"
[ "v$version" = "$ZOLA_TAG" ] || die "web/package.json version $version doesn't match UPSTREAM's $ZOLA_TAG"

OUT="$DIST_DIR/release"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$DIST_DIR/zola.wasm" "$OUT/"
gzip -9 --keep --no-name "$OUT/zola.wasm"

# npm pack takes the package's files as they are, so stage the wasm next to it for the duration
cp "$DIST_DIR/zola.wasm" "$ROOT/web/zola.wasm"
trap 'rm -f "$ROOT/web/zola.wasm"' EXIT
(cd "$ROOT/web" && npm pack --silent --pack-destination "$OUT" >/dev/null)
[ -f "$OUT/zola-wasi-$version.tgz" ] || die "npm pack didn't produce zola-wasi-$version.tgz"

sums="$(cd "$OUT" && sha256 ./* | sed 's#  \./#  #')"
echo "$sums" >"$OUT/SHA256SUMS"
log "Release assets in dist/release:"
for file in "$OUT"/*; do
  printf '  %-28s %s bytes\n' "$(basename "$file")" "$(wc -c <"$file" | tr -d ' ')" >&2
done
