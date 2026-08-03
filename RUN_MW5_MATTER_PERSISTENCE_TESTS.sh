#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXECUTABLE="${GODOT_BIN:-}"
MW5_TIMEOUT_SECONDS="${MW5_TIMEOUT_SECONDS:-300}"

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

if ! [[ "$MW5_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( MW5_TIMEOUT_SECONDS < 30 )); then
	echo "MW5_TIMEOUT_SECONDS must be an integer of at least 30 seconds." >&2
	exit 2
fi

if ! command -v timeout >/dev/null 2>&1; then
	echo "The coreutils timeout command is required by the bounded MW5 runner." >&2
	exit 2
fi

printf 'MW5 runner: starting with %ss timeout\n' "$MW5_TIMEOUT_SECONDS"
timeout --foreground --signal=TERM --kill-after=5s "${MW5_TIMEOUT_SECONDS}s" \
	"$GODOT_EXECUTABLE" \
	--headless \
	--path "$ROOT_DIR" \
	--script res://tests/matter/persistence/test_mw5_matter_persistence.gd
