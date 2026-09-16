#!/usr/bin/env bash
set -Eeuo pipefail
GODOT="${GODOT:-${GODOT_BIN:-godot}}"
"$GODOT" --headless --path . --script tests/research/fabric1/fabric_holdout_r4_g2_independent_verifier_r1.gd
