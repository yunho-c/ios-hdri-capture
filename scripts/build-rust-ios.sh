#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SRCROOT:-}" ]]; then
  ROOT_DIR="$SRCROOT"
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
CRATE_DIR="$ROOT_DIR/rust/hdri_encoder"
CONFIGURATION="${CONFIGURATION:-Debug}"
PLATFORM_NAME="${PLATFORM_NAME:-iphonesimulator}"

find_cargo() {
  if [[ -n "${CARGO:-}" && -x "${CARGO:-}" ]]; then
    echo "$CARGO"
    return
  fi

  if command -v cargo >/dev/null 2>&1; then
    command -v cargo
    return
  fi

  if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    echo "$HOME/.cargo/bin/cargo"
    return
  fi

  echo "error: cargo not found. Install Rust with rustup or set CARGO=/path/to/cargo." >&2
  exit 127
}

CARGO_BIN="$(find_cargo)"

if [[ "$CONFIGURATION" == "Release" ]]; then
  PROFILE_FLAG="--release"
  PROFILE_DIR="release"
else
  PROFILE_FLAG=""
  PROFILE_DIR="debug"
fi

export CARGO_BUILD_RUSTC_WRAPPER=
export RUSTC_WRAPPER=

build_target() {
  local rust_target="$1"
  "$CARGO_BIN" build \
    --manifest-path "$CRATE_DIR/Cargo.toml" \
    --target "$rust_target" \
    $PROFILE_FLAG
}

OUTPUT_DIR="$ROOT_DIR/Build/Rust/$PLATFORM_NAME"
mkdir -p "$OUTPUT_DIR"

case "$PLATFORM_NAME" in
  iphoneos)
    build_target "aarch64-apple-ios"
    cp "$CRATE_DIR/target/aarch64-apple-ios/$PROFILE_DIR/libhdri_encoder.a" "$OUTPUT_DIR/libhdri_encoder.a"
    ;;
  iphonesimulator)
    build_target "aarch64-apple-ios-sim"
    build_target "x86_64-apple-ios"
    xcrun lipo -create \
      "$CRATE_DIR/target/aarch64-apple-ios-sim/$PROFILE_DIR/libhdri_encoder.a" \
      "$CRATE_DIR/target/x86_64-apple-ios/$PROFILE_DIR/libhdri_encoder.a" \
      -output "$OUTPUT_DIR/libhdri_encoder.a"
    ;;
  *)
    echo "Unsupported PLATFORM_NAME: $PLATFORM_NAME" >&2
    exit 1
    ;;
esac
