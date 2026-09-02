#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
expected_version="4.7.1.stable.double.custom_build.a13da4feb"
[[ -x "$godot_bin" ]] || { echo "Godot binary not found: $godot_bin" >&2; exit 2; }
actual_version="$("$godot_bin" --version | head -n1 | tr -d '\r')"
[[ "$actual_version" == "$expected_version" ]] || { echo "Unexpected Godot version: $actual_version" >&2; exit 3; }
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
set +e
"$godot_bin" --headless --path "$repo_root" --script res://tests/research/fabric_bake0/fabric_bake_b0_4_c_acceptance.gd 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if [[ "$status" -ne 0 ]]; then exit "$status"; fi
if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
  echo "B0.4-C fatal script marker detected" >&2
  exit 4
fi
