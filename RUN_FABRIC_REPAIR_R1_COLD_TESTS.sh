#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${GODOT_BIN:?GODOT_BIN must point to canonical Godot 4.7.1 double}"
state_file="$(mktemp -p "${TMPDIR:-/tmp}" fabric-r1-cold-XXXXXX.json)"
trap 'rm -f "$state_file"' EXIT
export FABRIC_R1_COLD_STATE="$state_file"
export BREAKPOINT_RUNTIME_DISABLED=1
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_repair_r1_cold_writer.gd
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_repair_r1_cold_reader.gd
