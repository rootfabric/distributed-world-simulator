#!/usr/bin/env bash
set -euo pipefail

# ECO.EVO7 FFF6 focused repair suite (Ubuntu twin of RUN_ECO_EVO7_FFF6_TESTS.ps1).
#
# Runs the full FFF6 chain against the succession-lab boundary: the FFF6
# acceptance itself plus the FFF5..FFF0 dependency chain, the P1B/PH/P1A
# kernel and contract regressions, the cross-seed multiseed wave-2 battery,
# and the EVO6-WATER determinism regression (rule packs, fitness/evolution
# acceptances, visual observatory adapter) with a bit-identical result-hash
# guard on the frozen baseline.
#
# Required: double-precision Godot 4.7.1 custom build a13da4feb.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required (GODOT_BIN or \$1)" >&2
  exit 2
}

PYTHON_BIN="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_BIN" ]] || { echo "Python 3 required for the EVO6 rule-pack tests" >&2; exit 2; }

PROFILE="$ROOT/artifacts/test-results/eco-evo7-fff6-suite-$$"
mkdir -p "$PROFILE"

PASS_COUNT=0
FAIL_COUNT=0

# Frozen EVO6-WATER baseline (docs/checkpoints/2026-08-23_ECO_EVO7_FFF6_R1_RU.md,
# docs/evidence/2026-08-23_ECO_EVO7_FFF*_VERIFICATION_RU.md): the water
# evolution bridge must stay bit-identical through every chain change.
readonly EVO6_WATER_BASELINE_HASH="7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e"

run_invocation() {
  # run_invocation <name> <timeout> <command...>; returns the raw exit code,
  # writes stdout+stderr into PROFILE/<name>.log with an isolated HOME.
  local name="$1"
  local timeout_secs="$2"
  shift 2
  local home="$PROFILE/$name"
  mkdir -p "$home/data" "$home/config" "$home/cache"

  GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
  HOME="$home" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  timeout "$timeout_secs" "$@" >"$PROFILE/$name.log" 2>&1
}

godot_stage() {
  # Godot script stage: pass requires exit 0 + ": PASS" marker + no failure
  # markers anywhere in the log.
  local name="$1"
  local timeout_secs="$2"
  shift 2
  set +e
  run_invocation "$name" "$timeout_secs" "$GODOT_BIN" "$@"
  local exit_code=$?
  set -e
  local log="$PROFILE/$name.log"

  if [[ $exit_code == 0 ]] \
     && grep -q ': PASS' "$log" \
     && ! grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[eco-evo7-fff6-suite][stage] ${name^^}_PASS ($(grep -oE '[A-Za-z0-9.: _-]+: PASS \([0-9]+ assertions\)' "$log" | tail -1))"
  else
    FAIL_COUNT=$((PASS_COUNT + 1))
    echo "[eco-evo7-fff6-suite] FAIL $name (exit code $exit_code)" >&2
    tail -n 40 "$log" >&2
  fi
}

preflight_stage() {
  local name="editor-preflight"
  set +e
  run_invocation "$name" "600s" "$GODOT_BIN" --headless --editor --import --path "$ROOT"
  local exit_code=$?
  set -e
  local log="$PROFILE/$name.log"

  # Inherited defect NOT owned by this line: eco_evo4*/eco_evo5*.tscn carry a
  # BOM and may print "Parse Error: Expected '['" during the editor import
  # scan. Tolerate exactly those; anything else fails closed.
  local foreign_parse_errors
  foreign_parse_errors="$(grep 'Parse Error' "$log" | grep -Evc 'eco_evo[45]_.*\.tscn' || true)"
  if [[ $exit_code == 0 && "$foreign_parse_errors" == 0 ]] \
     && ! grep -Eq '(SCRIPT ERROR:|Compile Error:)' "$log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[eco-evo7-fff6-suite][stage] EDITOR_PREFLIGHT_OK"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[eco-evo7-fff6-suite] FAIL $name (exit code $exit_code, non-inherited parse errors: $foreign_parse_errors)" >&2
    tail -n 40 "$log" >&2
  fi
}

python_stage() {
  local name="$1"
  shift
  set +e
  run_invocation "$name" "120s" "$PYTHON_BIN" "$@"
  local exit_code=$?
  set -e
  local log="$PROFILE/$name.log"

  if [[ $exit_code == 0 ]] && ! grep -q '^FAIL ' "$log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[eco-evo7-fff6-suite][stage] ${name^^}_PASS"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[eco-evo7-fff6-suite] FAIL $name (exit code $exit_code)" >&2
    tail -n 40 "$log" >&2
  fi
}

water_hash_guard() {
  local name="evo6-water-baseline-hash-guard"
  local log="$PROFILE/eco_evo6_water_evolution_acceptance.log"
  if grep -q "result_hash=$EVO6_WATER_BASELINE_HASH" "$log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[eco-evo7-fff6-suite][stage] EVO6_WATER_BASELINE_HASH_GUARD_PASS (${EVO6_WATER_BASELINE_HASH:0:16}... bit-identical)"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[eco-evo7-fff6-suite] FAIL $name: expected result_hash $EVO6_WATER_BASELINE_HASH in the water evolution acceptance log" >&2
    grep -E 'result_hash' "$log" | tail -3 >&2 || true
  fi
}

## ------------------------------------------------------------- preflight ----

preflight_stage

## ------------------------------------------- FFF6 core + dependency chain ----

TESTS=(
  "eco_evo7_fff6_succession_lab_acceptance|900s|res://tests/research/ecology/eco_evo7_fff6_succession_lab_acceptance.gd"
  "eco_evo7_fff5_soil_memory_acceptance|600s|res://tests/research/ecology/eco_evo7_fff5_soil_memory_acceptance.gd"
  "eco_evo7_fff4_water_feedback_acceptance|600s|res://tests/research/ecology/eco_evo7_fff4_water_feedback_acceptance.gd"
  "eco_evo7_fff3_light_feedback_acceptance|600s|res://tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd"
  "eco_evo7_fff2_morphology_evolution_acceptance|600s|res://tests/research/ecology/eco_evo7_fff2_morphology_evolution_acceptance.gd"
  "eco_evo7_fff1_functional_phenotype_acceptance|600s|res://tests/research/ecology/eco_evo7_fff1_functional_phenotype_acceptance.gd"
  "eco_evo7_fff0_contract_mapping_acceptance|600s|res://tests/research/ecology/eco_evo7_fff0_contract_mapping_acceptance.gd"
  "eco_p1b_s1_mutation_lineage_acceptance|900s|res://tests/research/ecology/eco_p1b_s1_mutation_lineage_acceptance.gd"
  "eco_ph2_environment_coupled_development_acceptance|600s|res://tests/research/ecology/eco_ph2_environment_coupled_development_acceptance.gd"
  "eco_p1a_s1_environment_acceptance|600s|res://tests/research/ecology/eco_p1a_s1_environment_acceptance.gd"
  "eco_p1a_s2_single_plant_resource_acceptance|600s|res://tests/research/ecology/eco_p1a_s2_single_plant_resource_acceptance.gd"
  "eco_p1c_s4_aggregate_contract|600s|res://tests/research/ecology/eco_p1c_s4_aggregate_contract.gd"
  "eco_ph0_development_contract_acceptance|600s|res://tests/research/ecology/eco_ph0_development_contract_acceptance.gd"
)

for entry in "${TESTS[@]}"; do
  IFS='|' read -r name timeout_secs script <<<"$entry"
  godot_stage "$name" "$timeout_secs" --headless --path "$ROOT" --script "$script"
done

## ------------------------------------- cross-seed multiseed wave-2 battery ----

echo "[eco-evo7-fff6-suite] wiring in the canonical multiseed wave-2 battery"
set +e
"$ROOT/RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.sh" "$GODOT_BIN" >"$PROFILE/multiseed-wave2-runner.log" 2>&1
WAVE2_EXIT=$?
set -e
if [[ $WAVE2_EXIT == 0 ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[eco-evo7-fff6-suite][stage] MULTISEED_WAVE2_BATTERY_PASS"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "[eco-evo7-fff6-suite] FAIL multiseed-wave2 battery (exit code $WAVE2_EXIT)" >&2
  tail -n 40 "$PROFILE/multiseed-wave2-runner.log" >&2
fi

## --------------------------------------- EVO6-WATER determinism regression ----
# FINAL stage before the aggregate marker. Mirrors the tail step of
# RUN_ECO_EVO7_FFF6_TESTS.ps1 (commit c0a70efc), which invokes
# RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline. There is no direct .sh
# equivalent of that runner, so this block executes the same wrapped stages:
# the two python rule-pack tests, the water fitness + water-driven evolution
# acceptances and the visual observatory adapter under EVO6_WATER_LAB_AUTOCAP=1,
# preserving the bit-identical result_hash guard on the frozen baseline.

echo "[eco-evo7-fff6-suite] EVO6-WATER rule pack + numeric predicates"
python_stage test_evo5_rule_compiler "$ROOT/tests/research/ecology/test_evo5_rule_compiler.py"
python_stage test_evo6_water_rules "$ROOT/tests/research/ecology/test_evo6_water_rules.py"

godot_stage eco_evo6_water_fitness_acceptance 600s \
  --headless --path "$ROOT" --script res://tests/research/ecology/eco_evo6_water_fitness_acceptance.gd
godot_stage eco_evo6_water_evolution_acceptance 600s \
  --headless --path "$ROOT" --script res://tests/research/ecology/eco_evo6_water_evolution_acceptance.gd
water_hash_guard

echo "[eco-evo7-fff6-suite] EVO6-WATER visual observatory adapter"
set +e
EVO6_WATER_LAB_AUTOCAP=1 run_invocation eco_evo6_water_visual_adapter 600s \
  "$GODOT_BIN" --headless --path "$ROOT" res://scenes/labs/ecology/eco_evo6_water_evolution_lab.tscn
VISUAL_EXIT=$?
set -e
if [[ $VISUAL_EXIT == 0 ]] && grep -q 'ECO.EVO6-WATER-VIS: .*PASS plants=' "$PROFILE/eco_evo6_water_visual_adapter.log"; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[eco-evo7-fff6-suite][stage] EVO6_WATER_VISUAL_ADAPTER_PASS ($(grep -oE 'ECO.EVO6-WATER-VIS: .*PASS plants=[0-9]+' "$PROFILE/eco_evo6_water_visual_adapter.log" | tail -1))"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "[eco-evo7-fff6-suite] FAIL evo6-water visual adapter (exit code $VISUAL_EXIT)" >&2
  tail -n 40 "$PROFILE/eco_evo6_water_visual_adapter.log" >&2
fi

## ---------------------------------------------------------------- aggregate ----

echo "[eco-evo7-fff6-suite] passed: $PASS_COUNT failed: $FAIL_COUNT (logs: $PROFILE)"
(( FAIL_COUNT == 0 )) || exit 1

echo "[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF6_REPAIR_SUITE_PASS"
echo "[eco-evo7-fff6-suite][scope] interactive GUI lab runs, G5 C-mode screenshot evidence and the FFF7-scale forest runs are NOT covered by this suite; stability anti-runaway covers the two gated zones (MESIC_LOAM, DRY_SAND)"
