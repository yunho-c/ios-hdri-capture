#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SRCROOT:-}" ]]; then
  ROOT_DIR="$SRCROOT"
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
CRATE_DIR="$ROOT_DIR/rust/hdri_encoder"
OUT_DIR="$ROOT_DIR/Generated/UniFFI"

mkdir -p "$OUT_DIR"

export CARGO_BUILD_RUSTC_WRAPPER=
export RUSTC_WRAPPER=

cd "$CRATE_DIR"

cargo run \
  --bin uniffi-bindgen \
  -- generate "src/hdri_encoder.udl" \
  --language swift \
  --out-dir "$OUT_DIR"
