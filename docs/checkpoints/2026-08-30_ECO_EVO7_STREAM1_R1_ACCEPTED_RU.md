# ECO.EVO7 STREAM1 R1 — ACCEPTED

Дата: 2026-08-30  
Статус: **ACCEPTED / EXACT WINDOWS VERIFIED / PERF2.SIM AUTHORIZED**

## Accepted subject

Branch under verification:

```text
feature/eco-evo7-stream1-bounded-generation-stream-r1
```

Exact verified identity:

```text
HEAD  4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4
TREE  68389ef9a491fc2f1e13efb92058029c9536f870
PARENT e0d2cda22a431c69a1b3eb4c650d79627d8aea40
```

Frozen ancestors independently required by the mission remain ancestors of the accepted subject:

```text
PAR3 R3.2 predecessor
8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf

STREAM1 runtime code anchor
8636a525c47b524e0ef597e46f37ffe6204d27ee

verification harness anchor
e0d2cda22a431c69a1b3eb4c650d79627d8aea40
```

## Exact Windows verifier result

Environment:

```text
Godot
4.7.1.stable.double.custom_build.a13da4feb

fresh detached worktree
C:\distributed-world-simulator\eco-stream1-r1-verify
```

Verifier result:

```text
fresh detached worktree: PASS
import exit code:         PASS
source guards:            PASS
focused STREAM1:          PASS
focused assertions:       195
exact comparisons:        108/108
transitive gate:          PASS 11/11
final identity unchanged: PASS
worktree clean:           YES
```

Canonical focused marker:

```text
STREAM1 exact generation comparisons: 108
ECO.EVO7 STREAM1 Bounded Generation Stream: PASS (195 assertions)
```

Canonical transitive marker:

```text
ECO.EVO7 STREAM1 transitive acceptance: PASS
```

## Verified coverage

Focused acceptance proved:

```text
3 environment recipes
× chunk sizes 1 / 7 / 64
× 12 generations
= 108 exact canonical comparisons
```

and additionally:

- proposal hash invariance across chunk sizes;
- serial ↔ STREAM1 canonical parity;
- audit generations 1 and 10;
- forced chunk failure fail-closed;
- audit mismatch fail-closed;
- stale base rejection;
- current-parent binding rejection;
- malformed hereditary bundle rejection;
- corrupted proposal hash rejection;
- no partial generation commit;
- executor mutual exclusion;
- Workbench → LS3.4 → LS3.3 public seam.

Transitive gate passed the complete required chain:

```text
LS3.3
LS3.4
PERF1
PAR0
PAR0.2
PAR1
PAR2
PAR3
STREAM1
VIS3
PLAY0
```

## Pre-existing import warnings

Windows import returned exit code 0 while logging legacy scene parse warnings
(`Expected '['`) in:

```text
eco_evo5_probe2_tree_lab.tscn
eco_evo5_t51_creature_lab.tscn
eco_evo5_terrain_fly_lab.tscn
```

Verifier classified these as **PRE-EXISTING / NOT STREAM1 REGRESSION** because:

- those scenes are byte-unchanged relative to the STREAM1 predecessor;
- equivalent warnings exist in earlier accepted Windows verification logs;
- focused and transitive STREAM1 gates are green;
- exact tested identity remained unchanged.

This acceptance does not silently repair or reclassify those legacy scenes.

## Authority conclusion

STREAM1 R1 preserves the intended ownership model:

```text
bounded chunks
→ candidate / route / recruitment evidence
→ one full-generation proposal
→ LS3.3 validation
→ ONE atomic generation publication
```

Still forbidden:

- chunk-level commit authority;
- second ecology truth;
- STREAM1 persistence/network authority;
- hidden PAR2/PAR3 executor coexistence;
- proposal identity depending on chunk shape.

## Acceptance decision

The checkpoint condition from
`2026-08-30_ECO_EVO7_STREAM1_BOUNDED_GENERATION_STREAM_R1_RU.md`
is satisfied.

Therefore:

```text
ECO.EVO7 STREAM1 R1 = ACCEPTED
```

Accepted runtime/evidence identity is the verified subject SHA, not this later
metadata closure commit.

## Successor routing

Per the already-declared parallel execution policy:

```text
STREAM1 ACCEPTED
    ↓
PERF2.SIM   ← AUTHORIZED NOW

VIS4 / PLAY0.MORPH
    ↓
continues independently in parallel

STREAM1 ACCEPTED + PLAY0.MORPH ACCEPTED
    ↓
PERF2.CONV
    ↓
PLAY1 LIVING REGION
```

STREAM1 completion does **not** wait for PLAY0.MORPH before PERF2.SIM.

PERF2.SIM scope:

```text
PERF2.0 Measurement Contract
PERF2.1 STREAM1 Generation Profiling
PERF2.2 Working-set / Memory
PERF2.3 Simulation Scaling
PERF2.4 Runtime Optimization
```

PERF2.CONV remains blocked until the independent morphology/presentation lane is
accepted.

LS4 is not auto-dispatched by this closure.

## Evidence locations reported by Windows verifier

External Windows verification logs were reported at:

```text
C:\distributed-world-simulator\eco-stream1-r1-verify-logs\
C:\distributed-world-simulator\eco-stream1-r1-verify\artifacts\stream1_gate_logs\
```

These machine-local logs are external verifier evidence; the repository acceptance
record binds their reported verdict to the immutable tested HEAD/TREE above.
