#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 PAR0.2 BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
export ECO_PAR0_WORKER_LOG_DIR="${ECO_PAR0_WORKER_LOG_DIR:-$ROOT/artifacts/par0_worker_logs}"
export ECO_PAR0_SESSION_ROOT="${ECO_PAR0_SESSION_ROOT:-$ROOT/artifacts/par0_sessions}"
# PAR0.2 R1: inherited gates FIRST without any PAR0.2 activation (serial-
# default isolation), then PAR0 gates, then the focused PAR0.2 acceptance
# (dual verification, negative divergence, stale response, pool lifecycle).
TESTS=(
  "res://tests/ecology/eco_evo7_ls33_dispersal_recruitment_acceptance.gd"
  "res://tests/ecology/eco_evo7_ls34_local_competition_acceptance.gd"
  "res://tests/ecology/eco_evo7_perf1_generation_profiler_acceptance.gd"
  "res://tests/ecology/eco_evo7_vis3_planet_biome_viewer_acceptance.gd"
  "res://tests/ecology/eco_evo7_par0_recruitment_parity_acceptance.gd"
  "res://scripts/ecology/perf/eco_evo7_par0_transport_probe_v1.gd"
  "res://tests/ecology/eco_evo7_par02_dual_recruitment_acceptance.gd"
)
for TEST in "${TESTS[@]}"; do
  "$GODOT_BIN" --headless --path "$ROOT" --script "$TEST" 2> /dev/null
done
exit 0
