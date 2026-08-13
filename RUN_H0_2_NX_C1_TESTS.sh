#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_PATH:-${1:-godot}}"

TESTS=(
  "tests/network/test_nx_owner_movement_authority.gd"
  "tests/network/test_nx_render_physics_separation.gd"
  "tests/network/test_nx_owner_item_projection_rollback.gd"
  "tests/network/test_nx_client_tick_robustness.gd"
  "tests/network/test_nx6_predicted_item_interactions.gd"
)

printf '[H0.2][NX.C1] Godot: %s\n' "$GODOT_BIN"
for test_path in "${TESTS[@]}"; do
  printf '[H0.2][NX.C1] RUN %s\n' "$test_path"
  "$GODOT_BIN" --headless --path "$ROOT" --script "res://$test_path"
done
printf '[H0.2][NX.C1] focused suite PASS (%d scripts)\n' "${#TESTS[@]}"
