#!/usr/bin/env bash
# Serve the browser demo (web/demo) at http://127.0.0.1:${PORT:-8000}/
# Stages the demo, the library and dist/zola.wasm into dist/demo, rewriting the library's bare
# import of the WASI shim to a relative path (import maps don't reach Web Workers).
. "$(dirname "$0")/common.sh"

[ -f "$DIST_DIR/zola.wasm" ] || die "dist/zola.wasm missing: run scripts/build.sh first"
[ -d "$ROOT/web/node_modules" ] || (cd "$ROOT/web" && npm ci --silent)

STAGE="$DIST_DIR/demo"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$ROOT"/web/demo/* "$STAGE/"
cp -R "$ROOT/web/node_modules/@bjorn3/browser_wasi_shim/dist" "$STAGE/browser_wasi_shim"
sed 's#from "@bjorn3/browser_wasi_shim"#from "./browser_wasi_shim/index.js"#' "$ROOT/web/src/index.js" >"$STAGE/zola.js"
grep -q '"./browser_wasi_shim/index.js"' "$STAGE/zola.js" || die "couldn't rewrite the shim import in web/src/index.js"
cp "$DIST_DIR/zola.wasm" "$STAGE/"

PORT="${PORT:-8000}"
log "Serving the demo at http://127.0.0.1:$PORT/ (Ctrl-C to stop)"
cd "$STAGE" && exec python3 -m http.server "$PORT" --bind 127.0.0.1
