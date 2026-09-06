#!/usr/bin/env bash
# WP-TOOLS1: focused tooling test entry (Linux/macOS).
# Runs the authoring CLI tests, scale fixture tests and the WP1.0 contract
# predecessor regression. Exit code is pytest's exit code.
set -euo pipefail
cd "$(dirname "$0")/.."

python -m pytest \
    tests/world_packs/wp_cli \
    tests/world_packs/scale_fixtures \
    tests/world_packs/test_library_contract.py \
    -q
