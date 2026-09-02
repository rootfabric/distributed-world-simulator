# FABRIC.SYNC3 — Exact Verification Mission

Verify the exact SYNC-3 source carrier in a fresh detached checkout.

Required canonical engine:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Run:

```bash
set -Eeuo pipefail
godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"

test "$("$godot_bin" --version | head -n1 | tr -d '\r')" =   "4.7.1.stable.double.custom_build.a13da4feb"
test "$(sha256sum "$godot_bin" | awk '{print $1}')" =   "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"

BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" --headless --editor --path . --import
GODOT_BIN="$godot_bin" bash ./RUN_FABRIC_SYNC3_TESTS.sh

git diff --check
test -z "$(git status --porcelain=v1 --untracked-files=no)"
```

Required report:

- exact HEAD/TREE;
- source-carrier bundle SHA-256;
- Godot version/SHA;
- import exit and fatal marker count;
- B0.4-D focused count;
- B0.5-P0 focused count;
- SYNC-3 focused count;
- deterministic rerun of SYNC-3 focused test;
- Project Control result;
- final decision.

SYNC-3 is architecture synchronization, not production acceptance.
