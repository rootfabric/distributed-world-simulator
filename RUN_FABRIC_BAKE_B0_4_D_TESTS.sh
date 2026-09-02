#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
if [[ -z "$GODOT_BIN" ]]; then
  echo "GODOT_BIN or GODOT must point to canonical Godot" >&2
  exit 2
fi

"$GODOT_BIN" --headless --path . --script res://tests/research/fabric_bake0/fabric_bake_b0_4_d_acceptance.gd
