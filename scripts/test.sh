#!/usr/bin/env bash
# Full test suite. Builds what it needs first.
#
#   1. Upstream's CI checks on the patched tree: cargo fmt, build, test, and the docs site build
#   2. clippy on library and binary code, native and wasm32-wasip1, with warnings as errors
#   3. dist/zola.wasm under wasmtime: builds Zola's test sites and docs, compared with a native build
#   4. The JavaScript library (web/) in Node with the in-browser WASI shim, compared with wasmtime
#
# --quick skips 1 and 2.
. "$(dirname "$0")/common.sh"

quick=false
[ "${1:-}" = "--quick" ] && quick=true

"$ROOT/scripts/build.sh"
use_wasi_sdk

if ! $quick; then
  log "Upstream checks: fmt, build, test, docs"
  (
    cd "$ZOLA_DIR"
    cargo fmt --check
    cargo build --locked --all
    cargo test --locked --all
    docs_out="$(mktemp -d)"
    trap 'rm -rf "$docs_out"' EXIT
    (cd docs && cargo run --locked --quiet -- build --output-dir "$docs_out/public")
  )

  log "clippy (native and $TARGET)"
  (
    cd "$ZOLA_DIR"
    cargo clippy --locked --all -- -D warnings
    cargo clippy --locked --all --target "$TARGET" -- -D warnings
  )
fi

log "Native build for comparisons"
(cd "$ZOLA_DIR" && cargo build --locked --release)
NATIVE="$ZOLA_DIR/target/release/zola"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# build_site NAME: build $ZOLA_DIR/NAME natively and under wasmtime, each from a fresh copy
# (image processing writes into the site's static/), and compare the outputs.
build_site() {
  local name=$1
  mkdir -p "$WORK/native" "$WORK/wasm"
  cp -R "$ZOLA_DIR/$name" "$WORK/native/$name"
  cp -R "$ZOLA_DIR/$name" "$WORK/wasm/$name"
  "$NATIVE" --root "$WORK/native/$name" build --output-dir "$WORK/native/$name.out" >/dev/null
  "$WASMTIME" run --dir "$WORK/wasm::/work" "$DIST_DIR/zola.wasm" \
    --root "/work/$name" build --output-dir "/work/$name.out" >/dev/null
  python3 "$ROOT/tests/compare_outputs.py" "$WORK/native/$name.out" "$WORK/wasm/$name.out"
}

for site in test_site test_site_i18n docs; do
  log "wasmtime: $site matches native"
  build_site "$site"
done

log "wasmtime: check, and errors exit non-zero"
check_log="$("$WASMTIME" run --dir "$WORK/wasm/test_site::/site" "$DIST_DIR/zola.wasm" --root /site check 2>&1)" ||
  die "check failed: $check_log"
grep -q "External links can't be checked on WebAssembly" <<<"$check_log" || die "check didn't skip external links"
cp -R "$ZOLA_DIR/test_sites_invalid/indexmd" "$WORK/invalid"
if "$WASMTIME" run --dir "$WORK/invalid::/site" "$DIST_DIR/zola.wasm" --root /site build >/dev/null 2>&1; then
  die "building an invalid site succeeded"
fi

log "JavaScript library (Node, browser WASI shim)"
(
  cd "$ROOT/web"
  [ -d node_modules ] || npm ci --silent
  ZOLA_WASM="$DIST_DIR/zola.wasm" EXPECTED_DIR="$WORK/wasm/test_site.out" SITE_DIR="$ZOLA_DIR/test_site" \
    INVALID_SITE_DIR="$ZOLA_DIR/test_sites_invalid/indexmd" npm test --silent
)

log "All tests passed"
