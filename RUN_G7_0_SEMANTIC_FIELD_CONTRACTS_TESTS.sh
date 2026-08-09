#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-}"

if [[ -z "${GODOT_BIN}" ]]; then
  for candidate in \
    "${ROOT_DIR}/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64" \
    "${ROOT_DIR}/godot.linuxbsd.editor.double.x86_64" \
    "$(command -v godot 2>/dev/null || true)"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      GODOT_BIN="${candidate}"
      break
    fi
  done
fi

if [[ -z "${GODOT_BIN}" || ! -x "${GODOT_BIN}" ]]; then
  echo "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision editor binary." >&2
  exit 1
fi

export BREAKPOINT_RUNTIME_DISABLED=1

echo "=== G7.0 editor import / parse ==="
"${GODOT_BIN}" --headless --editor --path "${ROOT_DIR}" --quit

echo "=== G7.0 Semantic Field Contracts + Registry Vocabulary ==="
"${GODOT_BIN}" --headless --path "${ROOT_DIR}" --script res://tests/procedural/semantic_fields/g7_0_semantic_field_contracts_acceptance.gd

echo "G7.0 Semantic Field Contracts focused gate passed."
