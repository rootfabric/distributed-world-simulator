#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$ROOT/scripts/research/fabric_bake0/run_adaptive_fidelity_suite.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for count in 500 1000 2000; do
  args=(-- --count="$count")
  [[ "$count" == 500 ]] && args+=(--full-reference)
  bash "$helper" res://tests/research/fabric_bake0/fabric_bridge3_g_parity_scale_acceptance.gd \
    'FABRIC BRIDGE-3-G CASE: PASS' "${args[@]}" | tee "$tmp/$count.log"
done
python3 - "$tmp" <<'PY'
import hashlib, json, pathlib, sys
root=pathlib.Path(sys.argv[1])
rows=[]
for count in (500,1000,2000):
    lines=(root/f"{count}.log").read_text().splitlines()
    raw=[line.split('=',1)[1] for line in lines if line.startswith('BRIDGE3_G_CASE=')]
    if len(raw)!=1: raise SystemExit(f"missing/duplicate case {count}")
    row=json.loads(raw[0]); rows.append(row)
    if row['parts'] != count: raise SystemExit('scale mismatch')
    work=row['work']
    if work['reconstructed_parts'] != 20 or work['rebake_local_part_validations'] != 20: raise SystemExit('local work not bounded')
    if work['global_physical_rebuilds'] or work['duplicate_ownership_count']: raise SystemExit('unsafe global/duplicate work')
if not rows[0]['full_reference_checked'] or rows[1]['full_reference_checked'] or rows[2]['full_reference_checked']:
    raise SystemExit('reference scope mismatch')
canonical=json.dumps(rows,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
print('BRIDGE3_G_SUMMARIES='+json.dumps(rows,sort_keys=True,separators=(',',':')))
print('BRIDGE3_G_HASH='+hashlib.sha256(canonical).hexdigest())
print('FABRIC BRIDGE-3-G: PASS (3 independent scale processes)')
PY
