#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-}"

if [[ -z "$GODOT_EXECUTABLE" ]]; then
	for candidate in \
		"$ROOT_DIR/tools/godot/godot.linuxbsd.editor.double.x86_64" \
		"$ROOT_DIR/godot.linuxbsd.editor.double.x86_64" \
		"$(command -v godot 2>/dev/null || true)" \
		"$(command -v godot4 2>/dev/null || true)"; do
		if [[ -n "$candidate" && -x "$candidate" ]]; then
			GODOT_EXECUTABLE="$candidate"
			break
		fi
	done
fi

if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then
	echo "Godot executable not found. Set GODOT_BIN to the Godot 4.7.1 double-precision console/editor binary." >&2
	exit 2
fi

"$GODOT_EXECUTABLE" \
	--headless \
	--path "$ROOT_DIR" \
	--script res://tests/matter/contracts/test_mw0_matter_contracts.gd
