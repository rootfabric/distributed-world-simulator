#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
controller="$repo_root/tools/world_packs/parallel_controller.py"
python_bin="${PYTHON_BIN:-python3}"

action="${1:-status}"
shift || true

case "$action" in
  status|next)
    exec "$python_bin" "$controller" "$action" "$@"
    ;;
  instructions|verify)
    if [[ $# -lt 1 ]]; then
      echo "track id is required for $action" >&2
      exit 2
    fi
    track="$1"
    shift
    exec "$python_bin" "$controller" "$action" "$track" "$@"
    ;;
  *)
    echo "usage: $0 {status|next|instructions|verify} [TRACK] [--no-fetch] [--json]" >&2
    exit 2
    ;;
esac
