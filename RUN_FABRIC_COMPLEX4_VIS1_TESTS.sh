#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric1/fabric_complex4_vis1_playable_lab_acceptance.gd \
  'FABRIC COMPLEX4-VIS1 Playable Physical Lab: PASS'
