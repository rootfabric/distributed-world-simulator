#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric_bake0/fabric_bake_b0_6_import_smoke.gd \
  'FABRIC B0.6 Import Prerequisites: PASS'
