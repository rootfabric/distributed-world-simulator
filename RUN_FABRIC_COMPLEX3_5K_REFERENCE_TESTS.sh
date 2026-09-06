#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh" res://tests/research/fabric_bake0/fabric_complex3_5k_reference_acceptance.gd 'FABRIC COMPLEX3-5K REFERENCE: PASS'
