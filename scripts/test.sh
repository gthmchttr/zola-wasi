#!/usr/bin/env bash
# Full test suite. Builds what it needs first.
#
#   1. Upstream's CI checks on the patched tree: cargo fmt, build, test, and the docs site build
#   2. clippy on library and binary code, native and wasm32-wasip1, with warnings as errors
#   3. dist/zola.wasm under wasmtime: builds Zola's test sites and docs, compared with a native build
#   4. The JavaScript library (web/) in Node with the in-browser WASI shim, compared with wasmtime,
#      both from source and as the browser bundle (dist/zola-wasi.js)
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
    cd "$ZOLA_DIR" || exit
    cargo fmt --check
    cargo build --locked --all
    cargo test --locked --all
    docs_out="$(mktemp -d)"
    trap 'rm -rf "$docs_out"' EXIT
    (cd docs && cargo run --locked --quiet -- build --output-dir "$docs_out/public")
  )

  # Only warnings on lines the patches add fail the build: older Zola releases trip newer clippy
  # lints in their own code. Compile errors fail either way.
  log "clippy on the patched code (native and $TARGET)"
  (
    cd "$ZOLA_DIR" || exit
    # "file:line" for every line the patches add
    added="$(git diff -U0 "$ZOLA_TAG" wasi -- '*.rs' | awk '
      /^\+\+\+ b\// { file = substr($2, 3) }
      /^@@/ { split(substr($3, 2), range, ","); count = (range[2] == "" ? 1 : range[2])
              for (i = 0; i < count; i++) print file ":" range[1] + i }')"
    for target in "" "$TARGET"; do
      report="$(cargo clippy --locked --all --message-format=short ${target:+--target "$target"} 2>&1)" ||
        die "clippy failed${target:+ for $target}:"$'\n'"$report"
      ours="$(grep -E '^[^ ]+\.rs:[0-9]+:[0-9]+: (warning|error)' <<<"$report" |
        awk -F: 'NR == FNR { added[$0]; next } ($1 ":" $2) in added' <(echo "$added") - || true)"
      [ -z "$ours" ] || die "clippy warnings in patched code${target:+ for $target}:"$'\n'"$ours"
      others="$(grep -cE '^[^ ]+\.rs:[0-9]+:[0-9]+: warning' <<<"$report" || true)"
      [ "$others" = 0 ] || log "  ($others warning(s) in upstream code the patches don't touch)"
    done
  )
fi

log "Native build for comparisons"
(cd "$ZOLA_DIR" && cargo build --locked --release)
NATIVE="$ZOLA_DIR/target/release/zola"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# build_site NAME: build $ZOLA_DIR/NAME natively and under wasmtime, each from a fresh copy
# (image processing writes into the site's static/), and compare the outputs.
build_native() {
  local name=$1 run=$2
  mkdir -p "$WORK/$run"
  cp -R "$ZOLA_DIR/$name" "$WORK/$run/$name"
  "$NATIVE" --root "$WORK/$run/$name" build --output-dir "$WORK/$run/$name.out" >/dev/null
}

build_site() {
  local name=$1 builds=3 i
  mkdir -p "$WORK/wasm"
  cp -R "$ZOLA_DIR/$name" "$WORK/wasm/$name"
  "$WASMTIME" run --dir "$WORK/wasm::/work" "$DIST_DIR/zola.wasm" \
    --root "/work/$name" build --output-dir "/work/$name.out" >/dev/null
  # Extra native builds show which files Zola itself doesn't build deterministically. Any file
  # still differing gets up to 12 native builds: real mismatches are those every build agrees on.
  for i in $(seq 1 "$builds"); do build_native "$name" "native-$i"; done
  compare() {
    local others=()
    for i in $(seq 2 "$builds"); do others+=("$WORK/native-$i/$name.out"); done
    python3 "$ROOT/tests/compare_outputs.py" "$WORK/native-1/$name.out" "$WORK/wasm/$name.out" "${others[@]}"
  }
  until compare >/dev/null 2>&1 || [ "$builds" -ge 12 ]; do
    builds=$((builds + 1))
    build_native "$name" "native-$builds"
  done
  compare
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
  cd "$ROOT/web" || exit
  export ZOLA_WASM="$DIST_DIR/zola.wasm" EXPECTED_DIR="$WORK/wasm/test_site.out" SITE_DIR="$ZOLA_DIR/test_site" \
    INVALID_SITE_DIR="$ZOLA_DIR/test_sites_invalid/indexmd"
  # Files this Zola release doesn't build deterministically can't be compared byte for byte
  UNSTABLE_FILES="$(python3 "$ROOT/tests/compare_outputs.py" --unstable "$WORK"/native-*/test_site.out)"
  export UNSTABLE_FILES
  npm test --silent
  log "JavaScript browser bundle (dist/zola-wasi.js)"
  ZOLA_LIB="$DIST_DIR/zola-wasi.js" npm test --silent
)

log "All tests passed"
