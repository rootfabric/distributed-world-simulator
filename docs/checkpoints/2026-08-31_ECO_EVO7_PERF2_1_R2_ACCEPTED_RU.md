# ECO.EVO7 PERF2.1 R2 — ACCEPTED

Дата: 2026-08-31

Статус:

```text
PERF2.1 R2
ACCEPTED
EXACT LOCAL UBUNTU PASS
ECO-RUNTIME-VERIFY-2026-08-31-R1 SATISFIED
```

## Exact tested runtime subject

```text
branch
feature/eco-evo7-perf2-1-stream1-generation-profiling-r2

HEAD
fccf4f99fd3c257abf90c37e584b965e2cddfa6a

TREE
cdedc4686ebb85a07782a0065ee44d598e78ef9f
```

Implementation merge into the accepted ECO line:

```text
406e37b95b6b4969b0128df9f6fb35ab28c8bd38
```

The merge commit is not the tested executable identity. Runtime evidence belongs to
`fccf4f99fd3c257abf90c37e584b965e2cddfa6a`.

## Predecessor

```text
accepted PERF2.0 control base
07bffc0e7f30bac4479f1b7e53dee3fee3a818f6

frozen PERF2.0 contract blob
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Runtime verification policy

```text
config/ecology/eco-runtime-verification-policy.v1.json

revision
ECO-RUNTIME-VERIFY-2026-08-31-R1
```

PERF2.1 is OS-neutral GDScript/runtime. One fresh exact local execution on Ubuntu or
Windows is sufficient. Windows is optional/non-blocking cross-platform evidence.

For this acceptance:

```text
OS
Ubuntu

Godot
4.7.1.stable.double.custom_build.a13da4feb

host fingerprint
ee428a6139f8b5260a6626f4f7f375193144f9b5a9f280c59431470087c47d12
```

## Identity and ownership evidence

```text
remote branch exact            PASS
fresh detached worktree        PASS
base ancestry                  PASS
PERF2.0 contract frozen        PASS
protected runtime diff         PASS
final HEAD unchanged           PASS
final TREE unchanged           PASS
tracked worktree clean         YES
```

No accepted ecology/STREAM1/PERF2.0 runtime was modified by PERF2.1.

## Import

```text
Godot import exit              0
new parse errors               NONE
```

Known legacy ECO5 BOM parse warnings were present only in:

```text
eco_evo5_probe2_tree_lab.tscn
eco_evo5_t51_creature_lab.tscn
eco_evo5_terrain_fly_lab.tscn
```

These are pre-existing and outside PERF2.1 scope.

## Regression chain

```text
PERF1
PASS — 69 assertions

STREAM1
PASS — 195 assertions

STREAM1 exact
108 / 108

PERF2.0
PASS — 62 assertions

PERF2.1 R2
PASS — 861 assertions
```

## Canonical parity

```text
SERIAL_REFERENCE ↔ STREAM1 chunk 1
3 / 3 exact

SERIAL_REFERENCE ↔ STREAM1 chunk 7
3 / 3 exact

SERIAL_REFERENCE ↔ STREAM1 chunk 64
3 / 3 exact

TOTAL
9 / 9 exact
```

Exact canonical parity therefore holds across all measured execution configurations.

## JSON round-trip closure

Integer normalization:

```text
config normalization                    PASS
campaign context identity               PASS
fractional pseudo-int rejected          PASS
string pseudo-int rejected              PASS
```

Float/hash round-trip:

```text
stored report hash preserved            PASS
recomputed hash after JSON parse        PASS
full parsed report validation           PASS
+0.001 ms timing tamper rejected        PASS
```

The previous two Ubuntu REDs are considered resolved defects, not accepted evidence.

## Artifact

```text
samples
12

summaries
32

comparisons
3

report validation
PASS

working-set validation
PASS
```

Report identity:

```text
report hash
789c520d32656a70e1fcc86ac66096f7ceecaeccbd4ab8cd35a78172214b6ff1

campaign context hash
020c301296261bc88e8fd403bd99f6ef8f4c287a5ca9ab7116ecfddec3e7495e
```

The runtime-generated artifact itself remains machine-local evidence and is not canonical
world/ecology truth.

## Observed PERF2.1 profile

```text
chunk 1
wall serial/stream        0.895089
generation serial/stream  0.890065

chunk 7
wall serial/stream        0.887032
generation serial/stream  0.882825

chunk 64
wall serial/stream        0.908837
generation serial/stream  0.904516
```

All three ratios are below 1.0 on this host, so STREAM1 was slower than serial in this
measurement set. The least unfavorable wall ratio was chunk 64.

This is profiling evidence only:

```text
optimization_claim = false
```

PERF2.1 does not authorize an optimization claim.

## Verifier execution note

The verifier's first PERF2.1 invocation was started without the required
`ECO_PERF2_*` environment variables in that shell. Three identity preflight checks
failed before any profiling campaign ran.

The verifier then exported the exact identity variables and reran the same immutable
HEAD/TREE. The complete 861-assertion campaign passed.

Classification:

```text
VERIFIER ENVIRONMENT SETUP ERROR
NOT SUBJECT FAILURE
NO CODE REPAIR
NO WORKTREE MODIFICATION
```

Only the complete exact rerun is acceptance evidence.

## Acceptance decision

```text
PERF2.1 R2                     ACCEPTED
runtime acceptance             SATISFIED
Windows verification           NOT REQUIRED
second OS evidence             OPTIONAL
PERF2.2                        AUTHORIZED
```

Next checkpoint:

```text
ECO.EVO7/PERF2.2
Working-set / Memory
```
