# FABRIC-BAKE B0.4-D — independent exact verification mission

## Required subject

Verifier must use the exact current B0.4-D source-carrier subject. Do not verify a moving branch checkout.

## Required Godot

```text
version:
4.7.1.stable.double.custom_build.a13da4feb

Linux SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Procedure

```bash
set -Eeuo pipefail

godot_bin="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"

test "$("$godot_bin" --version | head -n1 | tr -d '\r')" = \
  "4.7.1.stable.double.custom_build.a13da4feb"

test "$(sha256sum "$godot_bin" | awk '{print $1}')" = \
  "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"

test -x RUN_FABRIC_BAKE_B0_4_D_TESTS.sh
test -x RUN_FABRIC_BAKE_B0_4_D_CLOSURE_TESTS.sh

git diff --check
test -z "$(git status --porcelain=v1 --untracked-files=no)"

BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" --headless --editor --path . --import
GODOT_BIN="$godot_bin" bash ./RUN_FABRIC_BAKE_B0_4_D_CLOSURE_TESTS.sh

git diff --check
test -z "$(git status --porcelain=v1 --untracked-files=no)"
```

## Required report

Record exact:

- detached HEAD;
- TREE;
- source carrier run/artifact/bundle SHA-256;
- Godot version and binary SHA-256;
- import exit/fatal-marker count;
- predecessor counts;
- B0.4-D focused assertion count;
- deterministic rerun result;
- final clean status and `git diff --check`;
- verdict.

Implementer self-verification is not sufficient for `CLOSED`. Independent Reviewer/Verifier evidence is required by project control.
