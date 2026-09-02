#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

printf 'HEAD=%s\n' "$(git rev-parse HEAD)"
printf 'TREE=%s\n' "$(git rev-parse 'HEAD^{tree}')"

bash ./RUN_FABRIC_BAKE_B0_3_TESTS.sh
bash ./RUN_FABRIC_BAKE_B0_4_A_TESTS.sh
bash ./RUN_FABRIC_BAKE_B0_4_B_TESTS.sh
bash ./RUN_FABRIC_BAKE_B0_4_C_TESTS.sh
bash ./RUN_FABRIC_BAKE_B0_4_D_TESTS.sh

echo "FABRIC-BAKE B0.4-D closure chain: PASS"
