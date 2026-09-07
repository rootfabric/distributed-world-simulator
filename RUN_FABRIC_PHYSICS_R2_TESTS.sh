#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric1/fabric_physics_r2_acceptance.gd \
  'FABRIC-PHYSICS-R2: PASS'

bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric1/fabric_physics_r2_contract_acceptance.gd \
  'FABRIC-PHYSICS-R2-CONTRACT: PASS'

bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric1/fabric_physics_r2_metamorphic_acceptance.gd \
  'FABRIC-PHYSICS-R2-METAMORPHIC: PASS'
