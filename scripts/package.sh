#!/usr/bin/env bash
# Assemble release assets from dist/zola.wasm (run scripts/build.sh first) into dist/release/:
#
#   zola.wasm                  Zola's CLI for wasm32-wasip1
#   zola.wasm.gz               the same, gzipped
#   zola-wasi.js               the JavaScript library with the WASI runtime built in, for browsers
#   zola-wasi-<version>.tgz    the JavaScript package (npm install ./zola-wasi-<version>.tgz), zola.wasm included
#   SHA256SUMS
. "$(dirname "$0")/common.sh"

for file in zola.wasm zola-wasi.js; do
  [ -f "$DIST_DIR/$file" ] || die "dist/$file missing: run scripts/build.sh first"
done
# The release's version is the Zola release it was built from (ZOLA_VERSION, or the newest in VERSIONS)
version="${ZOLA_TAG#v}"
built="$("$WASMTIME" run "$DIST_DIR/zola.wasm" --version)"
[ "$built" = "zola $version" ] || die "dist/zola.wasm is $built, not zola $version: run scripts/build.sh with the same ZOLA_VERSION"

OUT="$DIST_DIR/release"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$DIST_DIR/zola.wasm" "$OUT/"
gzip -9 --keep --no-name "$OUT/zola.wasm"
cp "$DIST_DIR/zola-wasi.js" "$OUT/"

# Stage the package with zola.wasm and the release's version, and pack that
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$ROOT/web/src" "$ROOT/web/package.json" "$ROOT/LICENSE" "$stage/"
cp "$DIST_DIR/zola.wasm" "$stage/"
python3 - "$stage/package.json" "$version" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
package = json.load(open(path))
package["version"] = version
json.dump(package, open(path, "w"), indent=2)
PY
(cd "$stage" && npm pack --silent --pack-destination "$OUT" >/dev/null)
[ -f "$OUT/zola-wasi-$version.tgz" ] || die "npm pack didn't produce zola-wasi-$version.tgz"

sums="$(cd "$OUT" && sha256 ./* | sed 's#  \./#  #')"
echo "$sums" >"$OUT/SHA256SUMS"
log "Release assets in dist/release:"
for file in "$OUT"/*; do
  printf '  %-28s %s bytes\n' "$(basename "$file")" "$(wc -c <"$file" | tr -d ' ')" >&2
done
