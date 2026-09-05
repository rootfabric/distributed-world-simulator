#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$ROOT/tests/research/fabric_bake0/test_adaptive_runner_contract.py"
