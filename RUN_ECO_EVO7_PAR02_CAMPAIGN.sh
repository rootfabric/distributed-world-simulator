#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-${GODOT_DOUBLE_BIN:-godot}}"
GENERATIONS="${GENERATIONS:-12}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$($GODOT_BIN --version | head -n 1 | tr -d '\r')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "ECO.EVO7 PAR0.2 CAMPAIGN BLOCKED: expected Godot '$EXPECTED', got '$ACTUAL'" >&2
  exit 2
fi
# Fresh coordinator process per run; one persistent pool per dual process.
export ECO_PAR0_WORKER_LOG_DIR="${ECO_PAR0_WORKER_LOG_DIR:-$ROOT/artifacts/par0_worker_logs}"
export ECO_PAR02_SESSION_ROOT="$ROOT/artifacts/par02_sessions"
ARTIFACT_DIR="$ROOT/artifacts/par02"
mkdir -p "$ARTIFACT_DIR"
export ECO_PAR02_BASE_SHA="$(git -C "$ROOT" rev-parse HEAD)"
export ECO_PAR02_CANDIDATE_SHA=""
export ECO_PAR02_GENERATIONS="$GENERATIONS"

RECIPES=(MIXED_PHYSICAL_HETEROGENEITY WATER_GRADIENT_STRONG RELIEF_DRAINAGE_STRONG)
WORKER_COUNTS=(1 2 4)

run() {
  local mode="$1" recipe="$2" workers="$3" artifact="$4" baseline="${5:-}"
  ECO_PAR02_MODE="$mode" ECO_PAR02_RECIPE="$recipe" ECO_PAR02_WORKERS="$workers" \
  ECO_PAR02_ARTIFACT="$artifact" ECO_PAR02_BASELINE_ARTIFACT="$baseline" \
  "$GODOT_BIN" --headless --path "$ROOT" \
    --script "res://scripts/ecology/perf/eco_evo7_par02_dual_campaign_runner_v1.gd" 2> /dev/null
}

# 1) Serial baselines: one fresh process per recipe, no executor, no pool.
for RECIPE in "${RECIPES[@]}"; do
  LOWER="$(echo "$RECIPE" | tr '[:upper:]' '[:lower:]')"
  run serial "$RECIPE" 0 "$ARTIFACT_DIR/serial_${LOWER}.json"
done

# 2) Dual canonical runs: fresh process per recipe/wc, one persistent pool,
#    12 verified generations each (3 x 3 x 12 = 108 comparisons).
for RECIPE in "${RECIPES[@]}"; do
  LOWER="$(echo "$RECIPE" | tr '[:upper:]' '[:lower:]')"
  for WORKERS in "${WORKER_COUNTS[@]}"; do
    run dual "$RECIPE" "$WORKERS" "$ARTIFACT_DIR/dual_${LOWER}_wc${WORKERS}.json" \
      "$ARTIFACT_DIR/serial_${LOWER}.json"
  done
done

# 3) Hash matrix + summary aggregation (fresh process).
"$GODOT_BIN" --headless --path "$ROOT" \
  --script "res://scripts/ecology/perf/eco_evo7_par02_campaign_matrix_v1.gd" 2> /dev/null
