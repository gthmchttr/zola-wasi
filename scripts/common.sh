# Shared settings for the scripts in this directory. Source it, don't run it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZOLA_DIR="$ROOT/zola"
TOOLCHAIN_DIR="$ROOT/.toolchain"
DIST_DIR="$ROOT/dist"
TARGET=wasm32-wasip1

# shellcheck source=../UPSTREAM
. "$ROOT/UPSTREAM"

WASI_SDK_VERSION=34.0
WASMTIME_VERSION=v50.0.0

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

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
