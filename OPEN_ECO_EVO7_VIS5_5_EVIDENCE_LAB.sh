#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
if [[ -z "${GODOT_BIN}" ]]; then
  echo "GODOT_BIN or GODOT must point to canonical double Godot" >&2
  exit 2
fi
exec "${GODOT_BIN}" --path "${ROOT}" res://scenes/labs/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff.tscn
