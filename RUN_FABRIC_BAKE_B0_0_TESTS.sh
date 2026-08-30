#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"

if [[ ! -x "$godot_bin" ]]; then
    echo "Godot binary not found or not executable: $godot_bin" >&2
    exit 2
fi

"$godot_bin" --headless --path "$repo_root" \
    --script res://tests/research/fabric_bake0/fabric_bake_b0_0_acceptance.gd
