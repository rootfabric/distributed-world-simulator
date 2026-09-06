#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
width="${1:?usage: RUN_FABRIC1_SCALE_CASE.sh WIDTH}"
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric1/fabric1_scale_acceptance.gd \
  "FABRIC1 Scale ${width}: PASS" -- --width="$width"
