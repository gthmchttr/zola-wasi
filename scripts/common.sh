# Shared settings for the scripts in this directory. Source it, don't run it.
# shellcheck shell=bash
# The variables here are used by the scripts that source this file
# shellcheck disable=SC2034
set -euo pipefail

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZOLA_DIR="$ROOT/zola"
TOOLCHAIN_DIR="$ROOT/.toolchain"
DIST_DIR="$ROOT/dist"
TARGET=wasm32-wasip1

# shellcheck source=../UPSTREAM
. "$ROOT/UPSTREAM"

# VERSIONS without comments and blank lines: "<tag> <commit>" per line
zola_versions() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$ROOT/VERSIONS"; }

# The Zola release to work on: ZOLA_VERSION (v0.23.6 or 0.23.6), else the newest in VERSIONS
if [ -n "${ZOLA_VERSION:-}" ]; then
  ZOLA_TAG="v${ZOLA_VERSION#v}"
else
  ZOLA_TAG="$(zola_versions | tail -n 1 | awk '{print $1}')"
fi
ZOLA_COMMIT="$(zola_versions | awk -v tag="$ZOLA_TAG" '$1 == tag {print $2}')"
[ -n "$ZOLA_COMMIT" ] || die "Zola $ZOLA_TAG is not in VERSIONS (supported: $(zola_versions | awk '{print $1}' | xargs))"

# The patch series for a Zola tag: patches/<tag>/ when that release needs its own, else
# patches/<vMAJOR.MINOR>/, shared by every release in that line.
series_dir() {
  local tag=$1 line
  line="$(echo "$tag" | cut -d. -f1-2)"
  if [ -f "$ROOT/patches/$tag/series" ]; then
    echo "$ROOT/patches/$tag"
  elif [ -f "$ROOT/patches/$line/series" ]; then
    echo "$ROOT/patches/$line"
  else
    die "no patches for Zola $tag: add patches/$line/series (or patches/$tag/series)"
  fi
}

# The patch files for a tag, in the order to apply them. A series file lists one path per line,
# relative to patches/, so a series can reuse another version's patches (e.g. v0.23/Foo.patch).
patch_files() {
  local dir entry
  dir="$(series_dir "$1")"
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$dir/series" | while read -r entry; do
    [ -f "$ROOT/patches/$entry" ] || die "${dir#"$ROOT"/}/series lists $entry, which doesn't exist"
    echo "$ROOT/patches/$entry"
  done
}

WASI_SDK_VERSION=34.0
WASMTIME_VERSION=v50.0.0

# sha256 FILE...: "<hash>  <file>" lines, with GNU coreutils or macOS's shasum
sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# os-arch as used in release asset names, e.g. "macos arm64"
host_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin) os=macos ;;
    Linux) os=linux ;;
    *) die "unsupported OS $(uname -s): only macOS and Linux are supported" ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=x86_64 ;;
    *) die "unsupported CPU $(uname -m)" ;;
  esac
  echo "$os $arch"
}

WASI_SDK_DIR="$TOOLCHAIN_DIR/wasi-sdk"
WASMTIME="$TOOLCHAIN_DIR/wasmtime/wasmtime"

# Point the cc crate at wasi-sdk so Zola's C dependencies (oniguruma, zstd, libwebp) build for WASI.
use_wasi_sdk() {
  [ -x "$WASI_SDK_DIR/bin/clang" ] || die "wasi-sdk missing: run scripts/toolchain.sh"
  export CC_wasm32_wasip1="$WASI_SDK_DIR/bin/clang"
  export AR_wasm32_wasip1="$WASI_SDK_DIR/bin/llvm-ar"
  export CFLAGS_wasm32_wasip1="--sysroot=$WASI_SDK_DIR/share/wasi-sysroot"
}
