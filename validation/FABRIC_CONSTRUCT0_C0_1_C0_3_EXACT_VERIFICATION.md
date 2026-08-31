# FABRIC CONSTRUCT0 C0.1–C0.3 — Independent Exact Verification

## Subject

Implementation/test subject:

```text
branch:
feature/fabric-construct0-tangible-sandbox-r1

HEAD:
d126f211a4b7749d6c80d0495740bcfb366f5d0d

TREE:
00fdb9ea041ae4a912037e4292c4c51fb270f676

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
git worktree add --detach ../dws-construct0-c03-verify d126f211a4b7749d6c80d0495740bcfb366f5d0d
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
HEAD d126f211a4b7749d6c80d0495740bcfb366f5d0d
TREE 00fdb9ea041ae4a912037e4292c4c51fb270f676
tracked worktree clean
```

## Fresh verifier procedure — Windows PowerShell

```powershell
git fetch origin --prune
git worktree add --detach C:\distributed-world-simulator\construct0-c03-verify d126f211a4b7749d6c80d0495740bcfb366f5d0d
Set-Location C:\distributed-world-simulator\construct0-c03-verify

git rev-parse HEAD
git rev-parse "HEAD^{tree}"
git status --short

$env:GODOT_BIN = "C:\path\to\godot.windows.editor.double.x86_64.console.exe"
.\RUN_FABRIC_CONSTRUCT0_C0_3_TESTS.ps1 -GodotPath $env:GODOT_BIN -ExpectedHead d126f211a4b7749d6c80d0495740bcfb366f5d0d
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

## Verdict

Only these verdicts are allowed:

```text
VERIFIED
```

or

```text
NOT_VERIFIED
```

Do not mark C0.1/C0.2/C0.3 CLOSED from code review alone.

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
