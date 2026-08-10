#!/usr/bin/env bash
set -euo pipefail

GODOT_PATH="${1:-${GODOT_BIN:-godot}}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
"$GODOT_PATH" --headless --path "$PROJECT_ROOT" --script res://tests/construction/ts0/ts0_fixture_contract_acceptance.gd
