#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"

GODOT_BIN="$godot_bin" bash "$repo_root/RUN_FABRIC_CONSTRUCT0_C0_5_TESTS.sh"

log="$(mktemp)"
set +e
"$godot_bin" --headless --path "$repo_root" --script res://tests/research/fabric_construct0/fabric_construct0_c0_6_acceptance.gd 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
if [[ "$status" -ne 0 ]]; then rm -f "$log"; exit "$status"; fi
if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
  echo "C0.6 fatal script marker detected" >&2
  rm -f "$log"
  exit 4
fi
rm -f "$log"
