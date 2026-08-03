#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCTION="$PROJECT_ROOT/scripts/world/testing/playground_runtime.gd"
CLIENT="$PROJECT_ROOT/tools/runtime/m7_playable_network_client.gd"
[[ -f "$PRODUCTION" ]] || { echo "Missing production playground runtime: $PRODUCTION" >&2; exit 2; }
[[ -f "$CLIENT" ]] || { echo "Missing M7 process client: $CLIENT" >&2; exit 2; }
grep -Fq '_m7_item_bridge.stop("NX6_PLAYGROUND_UNLOAD")' "$PRODUCTION" || {
  echo "NX6 fix3 production cleanup is not present." >&2
  exit 3
}
if grep -Fq 'nx6_lifecycle_safe_playground_runtime' "$CLIENT"; then
  echo "M7 process client still references the obsolete lifecycle wrapper." >&2
  exit 4
fi
rm -f \
  "$PROJECT_ROOT/scripts/world/testing/nx6_lifecycle_safe_playground_runtime.gd" \
  "$PROJECT_ROOT/scripts/world/testing/nx6_lifecycle_safe_playground_runtime.gd.uid"
echo "NX6 fix3 applied: production playground cleanup active; obsolete fix2 wrapper removed."
