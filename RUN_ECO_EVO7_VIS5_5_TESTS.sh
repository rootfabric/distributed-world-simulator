#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
if [[ -z "${GODOT_BIN}" ]]; then
  echo "GODOT_BIN or GODOT must point to canonical double Godot" >&2
  exit 2
fi
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$(${GODOT_BIN} --version | head -n 1 | tr -d '\r')"
if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
  echo "ECO.EVO7 VIS5.5 BLOCKED: expected Godot '${EXPECTED}', got '${ACTUAL}'" >&2
  exit 3
fi
export BREAKPOINT_RUNTIME_DISABLED=1
if [[ ! -f "${ROOT}/.godot/uid_cache.bin" ]]; then
  "${GODOT_BIN}" --headless --editor --path "${ROOT}" --import
fi
scripts=(
  res://tests/ecology/eco_evo7_vis5_0_terrain_ecosystem_composition_contract_acceptance.gd
  res://tests/ecology/eco_evo7_vis5_1_terrain_surface_frame_adapter_acceptance.gd
  res://tests/ecology/eco_evo7_vis5_2_noncanonical_ground_cover_bridge_acceptance.gd
  res://tests/ecology/eco_evo7_vis5_3_mixed_strata_composition_lab_acceptance.gd
  res://tests/ecology/eco_evo7_vis5_4_composition_lod_streaming_gate_acceptance.gd
  res://tests/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff_acceptance.gd
)
for script in "${scripts[@]}"; do
  echo "=== ${script} ==="
  "${GODOT_BIN}" --headless --path "${ROOT}" --script "${script}"
done
echo "ECO.EVO7 VIS5.5 Visual Evidence / Integrated PLAY1 Handoff candidate: PASS"
