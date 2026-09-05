#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh"
script='res://tests/research/fabric_bake0/fabric_bake_b0_6_d_persistence_restart_acceptance.gd'
bash "$helper" "$script" 'FABRIC B0.6-D Persistence Restart: PASS'
folder="$(mktemp -d)"
trap 'rm -rf "$folder"' EXIT
bash "$helper" "$script" 'FABRIC B0.6-D Disk Process: PASS' -- --write-capsule "$folder/capsule.json"
bash "$helper" "$script" 'FABRIC B0.6-D Disk Process: PASS' -- --read-capsule "$folder/capsule.json"
