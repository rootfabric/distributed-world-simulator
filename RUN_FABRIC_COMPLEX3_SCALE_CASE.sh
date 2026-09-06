#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
count="${1:?usage: RUN_FABRIC_COMPLEX3_SCALE_CASE.sh COUNT}"
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric_bake0/fabric_complex3_scale_acceptance.gd \
  'FABRIC COMPLEX3 SCALE CASE: PASS' -- --count="$count"
