#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${SRCROOT:-}" ]]; then
  ROOT_DIR="$SRCROOT"
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
CRATE_DIR="$ROOT_DIR/rust/hdri_encoder"
OUT_DIR="$ROOT_DIR/Generated/UniFFI"

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

mkdir -p "$OUT_DIR"

export CARGO_BUILD_RUSTC_WRAPPER=
export RUSTC_WRAPPER=

cd "$CRATE_DIR"

"$CARGO_BIN" run \
  --bin uniffi-bindgen \
  -- generate "src/hdri_encoder.udl" \
  --language swift \
  --out-dir "$OUT_DIR"
