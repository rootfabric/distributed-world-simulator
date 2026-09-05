#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
: "${GODOT_BIN:?Set GODOT_BIN to the project-attached canonical double executable}"
[[ -x "$GODOT_BIN" ]] || { echo "GODOT_BIN is not executable" >&2; exit 2; }
[[ "$("$GODOT_BIN" --version)" == '4.7.1.stable.double.custom_build.a13da4feb' ]] || exit 3
[[ "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" == 'bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7' ]] || exit 4
[[ $# == 2 ]] || { echo "Expected script resource and PASS sentinel" >&2; exit 2; }
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
export BREAKPOINT_RUNTIME_DISABLED=1
set +e
"$GODOT_BIN" --headless --path "$ROOT" --script "$1" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
[[ "$status" == 0 ]] || exit "$status"
if grep -Eq 'SCRIPT ERROR|Parse Error|Invalid call|Assertion failed|ERROR:|Segmentation fault' "$log"; then
  echo 'B0.6 fatal runtime marker: FAIL' >&2
  exit 5
fi
grep -Fq "$2" "$log" || { echo 'B0.6 PASS sentinel missing' >&2; exit 6; }
