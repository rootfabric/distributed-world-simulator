#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric1/fabric_complex4_bcd_e2e_acceptance.gd \
  'FABRIC COMPLEX4-BCD Real World Machine: PASS'
