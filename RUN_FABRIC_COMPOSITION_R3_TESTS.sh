#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh"
bash "$runner" res://tests/research/fabric1/fabric_composition_r3_acceptance.gd 'FABRIC-COMPOSITION-R3: PASS'
bash "$runner" res://tests/research/fabric1/fabric_composition_r3_observatory_acceptance.gd 'FABRIC-COMPOSITION-R3-OBSERVER: PASS'
evidence="${R3_REPLAY_DIR:-$ROOT/artifacts/fabric-composition-r3-process-replay}"
mkdir -p "$evidence"
bash "$runner" res://tests/research/fabric1/fabric_composition_r3_process_replay.gd 'FABRIC-COMPOSITION-R3-PROCESS-WRITE: PASS' -- write "$evidence"
bash "$runner" res://tests/research/fabric1/fabric_composition_r3_process_replay.gd 'FABRIC-COMPOSITION-R3-PROCESS-READ: PASS' -- read "$evidence"
