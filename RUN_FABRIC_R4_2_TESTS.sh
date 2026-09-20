#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to canonical Linux double Godot}"
PREREG="config/research/fabric-r4-2-preregistration.v1.json"
CHALLENGE="config/research/fabric-r4-2-challenge.v1.json"
python3 scripts/research/fabric_holdout_r42/r42.py protocol --prereg "$PREREG"
if [[ ! -f "$CHALLENGE" ]]; then
  echo "FABRIC-R4.2-PREREGISTRATION: PASS"
  exit 0
fi
python3 scripts/research/fabric_holdout_r42/r42.py verify --challenge "$CHALLENGE"
"$GODOT_BIN" --headless --path "$ROOT" --script res://tests/research/fabric1/fabric_r4_2_topology_dynamic_acceptance.gd -- "$CHALLENGE"
