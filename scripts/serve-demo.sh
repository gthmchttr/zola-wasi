#!/usr/bin/env bash
# Serve the browser demo (web/demo) at http://127.0.0.1:${PORT:-8000}/
# Stages the demo with the browser bundle (dist/zola-wasi.js) and dist/zola.wasm into dist/demo.
. "$(dirname "$0")/common.sh"

for file in zola.wasm zola-wasi.js; do
  [ -f "$DIST_DIR/$file" ] || die "dist/$file missing: run scripts/build.sh first"
done

STAGE="$DIST_DIR/demo"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$ROOT"/web/demo/* "$STAGE/"
cp "$DIST_DIR/zola.wasm" "$DIST_DIR/zola-wasi.js" "$STAGE/"

PORT="${PORT:-8000}"
log "Serving the demo at http://127.0.0.1:$PORT/ (Ctrl-C to stop)"
cd "$STAGE" && exec python3 -m http.server "$PORT" --bind 127.0.0.1
