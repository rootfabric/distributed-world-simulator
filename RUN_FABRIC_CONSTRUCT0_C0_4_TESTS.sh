#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
expected_version="4.7.1.stable.double.custom_build.a13da4feb"

if [[ ! -x "$godot_bin" ]]; then
  echo "Godot binary not found or not executable: $godot_bin" >&2
  exit 2
fi
actual_version="$("$godot_bin" --version | head -n 1 | tr -d '\r')"
[[ "$actual_version" == "$expected_version" ]] || { echo "Unexpected Godot version: $actual_version" >&2; exit 3; }

if [[ -f "$repo_root/RUN_FABRIC_CONSTRUCT0_PLAY1_TESTS.sh" ]]; then
  GODOT_BIN="$godot_bin" bash "$repo_root/RUN_FABRIC_CONSTRUCT0_PLAY1_TESTS.sh"
fi

log="$(mktemp)"
set +e
"$godot_bin" --headless --path "$repo_root" --script res://tests/research/fabric_construct0/fabric_construct0_c0_4_acceptance.gd 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if [[ "$status" -ne 0 ]]; then rm -f "$log"; exit "$status"; fi
if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
  echo "C0.4 fatal script marker detected" >&2
  rm -f "$log"
  exit 4
fi
rm -f "$log"
