#!/usr/bin/env bash
# Download the pinned wasi-sdk and wasmtime into .toolchain/, verifying their SHA-256.
# Also makes sure the Rust wasm32-wasip1 target is installed.
. "$(dirname "$0")/common.sh"

read -r OS ARCH < <(host_platform)

# Release asset digests, as published on GitHub.
wasi_sdk_sha256() {
  case "$1" in
    "macos arm64") echo 9c59398106b417f8f14913380fdf0097a8cc0ff4af9eb3ce0065a859e88d49e9 ;;
    "macos x86_64") echo 87d27fa8adc68dee59bfbf2e22a6d34ef717c34d6bf1d8af2a56fc929d9ce0eb ;;
    "linux arm64") echo f7e243dff54d60bcc576e94d6166b69f410f2500ae4a9ceef34315be10e77971 ;;
    "linux x86_64") echo b761e3a0721dbae9c09a0059e5fdb2bf917d1b4a8a7b430fb3b5aafb0984b2c4 ;;
  esac
}
wasmtime_sha256() {
  case "$1" in
    "macos arm64") echo 323dc098dc0455d60f396c404627e967b7033ffcfa29abfffb243126cf82c9d6 ;;
    "macos x86_64") echo ad14d9fb6a51d1633318426d6df21734127faddc81fe18a3afd70c5964eabeb5 ;;
    "linux arm64") echo 10f9ad1f8539d2e04e041cc622de6a270109ab1e43a6be1f69843c2082166832 ;;
    "linux x86_64") echo 77c19ee0437991f9ac7837b9c269d9c7076744f85dad263fea5214cc2723c7ff ;;
  esac
}

# fetch URL SHA256 DEST_DIR: download, verify and unpack an archive with a single top-level directory into DEST_DIR
fetch() {
  local url=$1 expected=$2 dest=$3 tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  log "Downloading $url"
  curl --fail --location --silent --show-error --output "$tmp/archive" "$url"
  local actual
  actual="$(sha256 "$tmp/archive" | cut -d" " -f1)"
  [ "$actual" = "$expected" ] || die "checksum mismatch for $url: expected $expected, got $actual"
  mkdir -p "$tmp/out"
  tar -xf "$tmp/archive" -C "$tmp/out"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  mv "$tmp/out"/* "$dest"
  # Downloads are quarantined on macOS, which blocks running the binaries
  if [ "$OS" = macos ]; then xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true; fi
}

if [ -x "$WASI_SDK_DIR/bin/clang" ] && [ "$(cat "$WASI_SDK_DIR/.version" 2>/dev/null)" = "$WASI_SDK_VERSION" ]; then
  log "wasi-sdk $WASI_SDK_VERSION already installed"
else
  fetch "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION%%.*}/wasi-sdk-$WASI_SDK_VERSION-$ARCH-$OS.tar.gz" \
    "$(wasi_sdk_sha256 "$OS $ARCH")" "$WASI_SDK_DIR"
  echo "$WASI_SDK_VERSION" >"$WASI_SDK_DIR/.version"
fi

if [ -x "$WASMTIME" ] && [ "$(cat "$TOOLCHAIN_DIR/wasmtime/.version" 2>/dev/null)" = "$WASMTIME_VERSION" ]; then
  log "wasmtime $WASMTIME_VERSION already installed"
else
  # wasmtime names arm64 "aarch64"
  fetch "https://github.com/bytecodealliance/wasmtime/releases/download/$WASMTIME_VERSION/wasmtime-$WASMTIME_VERSION-${ARCH/arm64/aarch64}-$OS.tar.xz" \
    "$(wasmtime_sha256 "$OS $ARCH")" "$TOOLCHAIN_DIR/wasmtime"
  echo "$WASMTIME_VERSION" >"$TOOLCHAIN_DIR/wasmtime/.version"
fi

command -v rustup >/dev/null || die "rustup not found: install Rust from https://rustup.rs"
if ! rustup target list --installed | grep -qx "$TARGET"; then
  log "Installing Rust target $TARGET"
  rustup target add "$TARGET"
fi

log "Toolchain ready: $("$WASI_SDK_DIR/bin/clang" --version | head -1), $("$WASMTIME" --version)"
