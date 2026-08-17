#!/usr/bin/env bash
set -Eeuo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/RUN_V0_SM0_P8_1_VISUAL_REFERENCE_FRAME_R1.sh" "$@"
