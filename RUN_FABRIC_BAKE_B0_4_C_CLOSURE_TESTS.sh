#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "FABRIC-BAKE B0.4-C closure chain"
echo "HEAD=$(git -C "$repo_root" rev-parse HEAD)"
echo "TREE=$(git -C "$repo_root" rev-parse 'HEAD^{tree}')"

"$repo_root/RUN_FABRIC_BAKE_B0_3_TESTS.sh"
"$repo_root/RUN_FABRIC_BAKE_B0_4_A_TESTS.sh"
"$repo_root/RUN_FABRIC_BAKE_B0_4_B_TESTS.sh"
"$repo_root/RUN_FABRIC_BAKE_B0_4_C_TESTS.sh"

echo "FABRIC-BAKE B0.4-C closure chain: PASS"
