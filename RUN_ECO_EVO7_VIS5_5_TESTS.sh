#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
if [[ -z "${GODOT_BIN}" ]]; then
  echo "GODOT_BIN or GODOT must point to canonical double Godot" >&2
  exit 2
fi
VERSION="$(${GODOT_BIN} --version)"
case "${VERSION}" in
  4.7.1.stable.double.custom_build.a13da4feb*) ;;
  *) echo "Unexpected Godot: ${VERSION}" >&2; exit 3 ;;
esac
bash "${ROOT}/RUN_ECO_EVO7_VIS5_4_TESTS.sh"
"${GODOT_BIN}" --headless --path "${ROOT}" --script res://tests/ecology/eco_evo7_vis5_5_visual_evidence_play1_handoff_acceptance.gd
