#!/usr/bin/env bash
set -Eeuo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$script_dir/RUN_V0_SM0_P8_1_VISUAL_REFERENCE_FRAME_R1.sh" "$@"
