#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case_name="${1:?usage: RUN_FABRIC_B0_7_TESTS.sh alpha|beta|gamma|guard}"
case "$case_name" in alpha|beta|gamma|guard) ;; *) echo "invalid B0.7 case: $case_name" >&2; exit 2;; esac
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" \
  res://tests/research/fabric_bake0/fabric_bake_b0_7_unseen_machine_acceptance.gd \
  'FABRIC-BAKE B0.7 UNSEEN MACHINE: PASS' -- --case="$case_name"
