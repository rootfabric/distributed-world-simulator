#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
export GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"

bash ./RUN_FABRIC_SYNC4_TESTS.sh
bash ./RUN_FABRIC_BRIDGE2_TESTS.sh

echo "FABRIC BRIDGE-2 R1 closure chain: PASS"
