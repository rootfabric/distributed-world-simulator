#!/usr/bin/env bash
# Portable standard-precision smoke, NOT self-hosted double exact.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
if grep -Eq '^config/features=PackedStringArray\("4\.8"' "$root/project.godot"; then
  tag="4.8-beta1"
  version_prefix="4.8.beta1."
  sha="199b2d6a0daa3a74a697356f31c33347f997f65258ba7dd07ca8c1110757927d"
else
  tag="4.7.1-stable"
  version_prefix="4.7.1.stable."
  sha="c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba"
fi
engine_dir="$(mktemp -d)"
zip="$engine_dir/official.zip"
url="https://github.com/godotengine/godot-builds/releases/download/$tag/Godot_v$tag""_linux.x86_64.zip"
curl -fsSL --retry 3 "$url" -o "$zip"
printf '%s  %s\n' "$sha" "$zip" | sha256sum -c -
unzip -q "$zip" -d "$engine_dir"
binary="$engine_dir/Godot_v$tag""_linux.x86_64"
chmod +x "$binary"
version="$("$binary" --version | tr -d '\r')"
case "$version" in "$version_prefix"*) ;; *) echo "DWS_PORTABLE_SMOKE_VERSION_MISMATCH:$version" >&2; exit 5 ;; esac
if [[ -n "$(printenv GITHUB_ENV || true)" ]]; then
  printf 'DWS_PORTABLE_GODOT_BIN=%s\n' "$binary" >> "$GITHUB_ENV"
fi
printf 'DWS_PORTABLE_GODOT_BIN=%s\nDWS_PORTABLE_SHA256=%s\nDWS_PORTABLE_VERSION=%s\nDWS_PORTABLE_PRECISION=standard_smoke_not_double_exact\n' "$binary" "$sha" "$version"
