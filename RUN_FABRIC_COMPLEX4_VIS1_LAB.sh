#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
exec "$GODOT_BIN" --path "$ROOT" --scene res://scenes/labs/fabric/complex4_playable_physical_lab.tscn
