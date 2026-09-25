#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
: "${GODOT_BIN:?Set GODOT_BIN to the pinned canonical double engine}"
EXPECTED=bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
test "$(sha256sum "$GODOT_BIN" | cut -d' ' -f1)" = "$EXPECTED"
test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = '4.7.1.stable.double.custom_build.a13da4feb'
OUT="${T12_EVIDENCE_DIR:-$ROOT/artifacts/fabric-r5-2-t12}"
mkdir -p "$OUT"
export GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1
printf 'HEAD=%s\nTREE=%s\nGODOT_SHA256=%s\n' "$(git rev-parse HEAD)" "$(git rev-parse 'HEAD^{tree}')" "$EXPECTED" > "$OUT/identity.txt"
test -z "$(git status --porcelain=v1 --untracked-files=no)"
timeout --kill-after=5s 120s "$GODOT_BIN" --headless --editor --path "$ROOT" --import >"$OUT/import.log" 2>&1
! grep -Ei 'SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:' "$OUT/import.log"
for i in 1 2 3; do
  /usr/bin/time -v -o "$OUT/sample-$i.time.txt" \
    timeout --kill-after=5s 180s "$GODOT_BIN" --headless --path "$ROOT" \
    --script res://tests/research/fabric_bake0/fabric_r5_2_t12_ship_acceptance.gd \
    >"$OUT/sample-$i.log" 2>&1
  grep -F 'FABRIC R5.2 T12 SHIP MATRYOSHKA: PASS' "$OUT/sample-$i.log"
done
python3 scripts/research/fabric_bake0/collect_r5_2_t12_evidence.py --root "$OUT" --out "$OUT/evidence.json"
test -z "$(git status --porcelain=v1 --untracked-files=no)"
