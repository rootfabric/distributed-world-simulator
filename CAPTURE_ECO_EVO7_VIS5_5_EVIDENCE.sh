#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${GODOT:-}}"
OUT="${1:-${ROOT}/artifacts/eco_vis5_5_visual_evidence}"
if [[ -z "${GODOT_BIN}" ]]; then
  echo "GODOT_BIN or GODOT must point to canonical double Godot" >&2
  exit 2
fi
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL="$(${GODOT_BIN} --version | head -n 1 | tr -d '\r')"
if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
  echo "Expected canonical double Godot '${EXPECTED}', got '${ACTUAL}'" >&2
  exit 3
fi
mkdir -p "${OUT}"
if command -v xvfb-run >/dev/null 2>&1; then
  DWS_VIS55_EVIDENCE_DIR="${OUT}" xvfb-run -a -s '-screen 0 1280x720x24' \
    "${GODOT_BIN}" --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 \
    --path "${ROOT}" --script res://tests/ecology/eco_evo7_vis5_5_capture_evidence.gd
elif [[ -n "${DISPLAY:-}" ]]; then
  DWS_VIS55_EVIDENCE_DIR="${OUT}" "${GODOT_BIN}" --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 \
    --path "${ROOT}" --script res://tests/ecology/eco_evo7_vis5_5_capture_evidence.gd
else
  echo "VIS5.5 graphical capture requires xvfb-run or an active DISPLAY" >&2
  exit 4
fi
