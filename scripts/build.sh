#!/usr/bin/env bash
# Build dist/zola.wasm, Zola's CLI for wasm32-wasip1, from the pinned release plus patches/,
# and dist/zola-wasi.js, the self-contained browser bundle of the JavaScript library.
# Runs toolchain.sh and setup.sh first (setup keeps an existing ./zola checkout).
. "$(dirname "$0")/common.sh"

"$ROOT/scripts/toolchain.sh"
"$ROOT/scripts/setup.sh" --keep
use_wasi_sdk

log "Building zola for $TARGET"
(cd "$ZOLA_DIR" && cargo build --locked --release --target "$TARGET")

mkdir -p "$DIST_DIR"
cp "$ZOLA_DIR/target/$TARGET/release/zola.wasm" "$DIST_DIR/zola.wasm"
(cd "$DIST_DIR" && sha256 zola.wasm >zola.wasm.sha256)

log "Bundling the JavaScript library"
(cd "$ROOT/web" && { [ -d node_modules ] || npm ci --silent; } && npm run --silent bundle)

version="$("$WASMTIME" run "$DIST_DIR/zola.wasm" --version)"
log "Built $version: dist/zola.wasm ($(du -h "$DIST_DIR/zola.wasm" | cut -f1), $(gzip -9 -c "$DIST_DIR/zola.wasm" | wc -c | awk '{printf "%.1f MB", $1/1048576}') gzipped) and dist/zola-wasi.js ($(du -h "$DIST_DIR/zola-wasi.js" | cut -f1))"
