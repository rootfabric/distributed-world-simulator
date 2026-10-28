#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${1:-${GODOT_BIN:-godot}}"
LOG_DIR="${N3_R0_LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/n3-r0-contracts.XXXXXXXX")}"
mkdir -p "$LOG_DIR"

PYTHON_BIN="${N3_R0_PYTHON:-}"
if [[ -z "$PYTHON_BIN" ]]; then
    for executable in python3 python; do
        # Verify the candidate actually runs: on Windows Git Bash,
        # "python3" can resolve to the Microsoft Store stub, which exits
        # non-zero without executing anything.
        if command -v "$executable" >/dev/null 2>&1 \
                && "$executable" -c "pass" >/dev/null 2>&1; then
            PYTHON_BIN="$executable"
            break
        fi
    done
fi
if [[ -z "$PYTHON_BIN" ]]; then
    echo 'N3_R0_PYTHON_MISSING: cannot validate native test receipts' >&2
    exit 2
fi

for test_script in tests/network/test_n3_region_directory_contracts.gd tests/network/test_n3_directory_b0_routes.gd; do
    test_name="$(basename "$test_script" .gd)"
    expected_id="${test_name#test_}"
    log="$LOG_DIR/$test_name.log"
    status=0
    "$GODOT_BIN" --headless --path "$ROOT" --script "res://$test_script" >"$log" 2>&1 || status=$?
    cat "$log"
    if (( status != 0 )); then
        echo "N3_NATIVE_NONZERO_EXIT: $test_name (exit=$status; log=$log)" >&2
        exit 1
    fi
    if ! "$PYTHON_BIN" - "$log" "$expected_id" <<'PY'
import json
import pathlib
import re
import sys

log_path = pathlib.Path(sys.argv[1])
expected_test_id = sys.argv[2]
text = log_path.read_text(encoding="utf-8", errors="replace")
error_signatures = re.compile(
    r"SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|Error compiling|\[n3-(?:r0|b0)\]\[FAIL\]",
    re.IGNORECASE,
)
if error_signatures.search(text):
    raise SystemExit(f"N3_NATIVE_LOG_ERROR: {expected_test_id}")

receipts = []
for line in text.splitlines():
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict) and ("test" in value or "verdict" in value):
        receipts.append(value)
if len(receipts) != 1:
    raise SystemExit(f"N3_NATIVE_RECEIPT_COUNT: {expected_test_id}: {len(receipts)}")
receipt = receipts[0]
if (receipt.get("test") != expected_test_id
        or receipt.get("verdict") != "PASS"
        or type(receipt.get("assertions")) is not int
        or receipt["assertions"] < 1
        or receipt.get("failures") != []):
    raise SystemExit(f"N3_NATIVE_INVALID_RECEIPT: {expected_test_id}: {receipt!r}")
print(f"N3_NATIVE_VERIFIED: {expected_test_id}: {receipt['assertions']} assertions")
PY
    then
        echo "N3_NATIVE_FAIL_CLOSED: $test_name (log=$log)" >&2
        exit 1
    fi
done

echo "N3_R0_NATIVE_PASS: $LOG_DIR"
