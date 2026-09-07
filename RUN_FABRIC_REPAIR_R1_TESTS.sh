#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric1/fabric_repair_r1_integrity_acceptance.gd \
  'FABRIC-REPAIR-R1 INTEGRITY: PASS'
