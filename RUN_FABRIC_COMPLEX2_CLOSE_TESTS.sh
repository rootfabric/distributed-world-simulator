#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${ROOT}/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64}"
if [[ ! -x "$GODOT_BIN" ]]; then
  echo "COMPLEX2-CLOSE requires canonical Linux double Godot via GODOT_BIN" >&2
  exit 2
fi
exec "$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric_bake0/fabric_bake_complex2_close_acceptance.gd
