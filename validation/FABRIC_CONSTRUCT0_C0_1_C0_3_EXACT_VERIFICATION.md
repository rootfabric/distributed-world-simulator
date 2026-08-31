# FABRIC CONSTRUCT0 C0.1–C0.3 — Independent Exact Verification

## Subject

Implementation/test subject:

```text
branch:
feature/fabric-construct0-tangible-sandbox-r1

HEAD:
837c46940acddbd841e7878dcfbfb68c0d5ac259

TREE:
8a554f9d7e45660aa6a4354c62742b4432633523

base B0.3 closure:
9575a63d6aeb4c455f8beade7588505e600c12d6
```

This subject contains C0.1 SEE THE MODEL, C0.2 SEE FABRIC MOVE IT, C0.3 BUILD IT, focused acceptance scripts, Linux chained runner and Windows exact runner. The verifier must not inherit execution evidence from the implementer.

## Godot identity

Required:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Canonical Linux binary SHA-256:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Canonical Linux archive SHA-256:

```text
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

Build identity:

```text
Godot 4.7.1-stable
commit a13da4feb8d8aefc283c3763d33a2f170a18d541
platform linuxbsd
target editor
arch x86_64
precision double
```

## Fresh verifier procedure — Ubuntu/Linux

```bash
git fetch origin --prune
git worktree add --detach ../dws-construct0-c03-verify 837c46940acddbd841e7878dcfbfb68c0d5ac259
cd ../dws-construct0-c03-verify

git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
git status --short

export GODOT_BIN=/absolute/path/to/godot.linuxbsd.editor.double.x86_64
"$GODOT_BIN" --version
sha256sum "$GODOT_BIN"

BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN" --headless --path . --import
GODOT_BIN="$GODOT_BIN" bash ./RUN_FABRIC_CONSTRUCT0_C0_3_TESTS.sh
```

Required identity:

```text
HEAD 837c46940acddbd841e7878dcfbfb68c0d5ac259
TREE 8a554f9d7e45660aa6a4354c62742b4432633523
tracked worktree clean
```

## Fresh verifier procedure — Windows PowerShell

```powershell
git fetch origin --prune
git worktree add --detach C:\distributed-world-simulator\construct0-c03-verify 837c46940acddbd841e7878dcfbfb68c0d5ac259
Set-Location C:\distributed-world-simulator\construct0-c03-verify

git rev-parse HEAD
git rev-parse "HEAD^{tree}"
git status --short

$env:GODOT_BIN = "C:\path\to\godot.windows.editor.double.x86_64.console.exe"
.\RUN_FABRIC_CONSTRUCT0_C0_3_TESTS.ps1 -GodotPath $env:GODOT_BIN -ExpectedHead 837c46940acddbd841e7878dcfbfb68c0d5ac259
```

## Required acceptance

### C0.1 — SEE THE MODEL

Must prove:
- TABLE / BRIDGE / CART / PLANK canonical Construction presets validate;
- runtime projection materializes;
- controlled 21×21 support fixture enters real B0.3;
- FULL member count 441;
- BAKED extreme generator count 4 for the reference rectangles;
- meaningful reduction;
- reversed contact order is deterministic;
- passivity holds;
- unsupported non-coplanar patch returns explicit NO_SAFE_BAKE;
- lab scene parses and instantiates.

### C0.2 — SEE FABRIC MOVE IT

Must prove:
- direct closed FABRIC0.18 persistent-contact trajectory executes;
- impact acquisition is first;
- stick→slide, stick→roll, stick→spin, support→separation events are visible and causal;
- free-flight display projection descends before impact;
- STEP EVENT reaches exact event boundaries;
- final display pose/velocities are finite;
- quaternion stays normalized;
- repeat exact trajectory has identical signature and timeline.

C0.2 is a display projection. It does not promote Godot physics state to FABRIC truth.

### C0.3 — BUILD IT

Must prove:
- generic canonical `update_part_pose` advances Construction revision/checksum;
- exact operation replay is idempotent;
- conflicting replay is rejected;
- stale revision is rejected;
- editor creates BLOCK / PLATE / BEAM;
- move and rotate mutate canonical state;
- RIGID bond creation is canonical;
- bond break sets Construction to DAMAGED;
- runtime projection recompiles edited parts;
- device-specific shortcut such as MOTOR is rejected by the C0.3 palette.

## Project Control

Project Control must PASS on the exact implementation/test subject or an evidence-only descendant that contains it unchanged.

## Exact verification result

Verification was executed from a fresh detached worktree reconstructed from an exact Git bundle produced by a GitHub Actions carrier that checked out the subject SHA explicitly.

```text
SUBJECT HEAD:
837c46940acddbd841e7878dcfbfb68c0d5ac259

SUBJECT TREE:
8a554f9d7e45660aa6a4354c62742b4432633523

tracked status:
clean

bundle SHA-256:
dc54bdfbbb8c6272090ce9e1629320ca6aa14f508d3a332e8812203ddf8cb46c

Godot:
4.7.1.stable.double.custom_build.a13da4feb

Godot binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

Godot archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92

import:
PASS, exit 0

known unrelated historical ECO scene diagnostics:
present, non-fatal, unchanged

C0.1:
PASS (58 assertions)

C0.2:
PASS (33 assertions)

C0.3:
PASS (30 assertions)

chained runner:
PASS, exit 0

Project Control exact subject:
run 33431191889
SUCCESS

Exact source carrier:
run 33431220738
SUCCESS
artifact 9772649470
```

Verdict:

```text
VERIFIED
```

C0.1/C0.2/C0.3 may now be qualified CLOSED as research/demo checkpoints. Production acceptance is not claimed.

## Next after VERIFIED

```text
C0.1 CLOSED
C0.2 CLOSED
C0.3 CLOSED
        ↓
CONSTRUCT0.PLAY1
PHYSICAL TOYBOX
```

The next implementation checkpoint is PLAY1, beginning with the generic part/relation vocabulary and mandatory toybox experiments from the CONSTRUCT roadmap.
