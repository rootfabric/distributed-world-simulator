#!/usr/bin/env bash
# Strict SHA-pinned 4.8 vs 4.7.1 identity according to project.godot marker.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
[[ -f "$root/project.godot" ]] || { echo DWS_PROJECT_MARKER_MISSING >&2; exit 2; }
if grep -Eq '^config/features=PackedStringArray\("4\.8"' "$root/project.godot"; then
  expected_version="4.8.beta1.double.custom_build.4d10419ca"
  expected_sha="4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f"
  first="$(printenv DWS_ENGINE48_GODOT_LINUX_BIN || true)"
  second="$HOME/.local/opt/godot-double-4.8-beta1/godot.linuxbsd.editor.double.x86_64"
  third="/home/rdpuser/.local/opt/godot-double-4.8-beta1/godot.linuxbsd.editor.double.x86_64"
  is_48=1
else
  expected_version="4.7.1.stable.double.custom_build.a13da4feb"
  expected_sha="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
  first="$(printenv DWS_GODOT_DOUBLE_LINUX_BIN || true)"
  second="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
  third=""
  is_48=0
fi
selected=""
for candidate in "$first" "$second" "$third"; do
  [[ -n "$candidate" && -x "$candidate" ]] || continue
  actual_sha="$(sha256sum "$candidate" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || continue
  selected="$(realpath "$candidate")"
  break
done
[[ -n "$selected" ]] || { echo "DWS_EXACT_LINUX_BINARY_NOT_FOUND:$expected_sha" >&2; exit 3; }
actual_version="$("$selected" --version | tr -d '\r')"
[[ "$actual_version" == "$expected_version" ]] || { echo "DWS_EXACT_LINUX_VERSION_MISMATCH:$actual_version" >&2; exit 4; }
if [[ -n "$(printenv GITHUB_ENV || true)" ]]; then
  printf 'DWS_GODOT_DOUBLE_LINUX_BIN=%s\n' "$selected" >> "$GITHUB_ENV"
  if (( is_48 )); then printf 'DWS_ENGINE48_GODOT_SHA256=%s\n' "$expected_sha" >> "$GITHUB_ENV"; fi
fi
printf 'DWS_EXACT_ENGINE_RESOLVED=%s\nDWS_EXACT_ENGINE_SHA256=%s\nDWS_EXACT_ENGINE_VERSION=%s\n' "$selected" "$expected_sha" "$actual_version"
