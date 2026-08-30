# ECO.EVO7 STREAM1 R1 — Windows Acceptance

Статус: **ACCEPTED**.

## Frozen verified target

```text
branch:
feature/eco-evo7-stream1-bounded-generation-stream-r1

HEAD:
4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4

TREE:
68389ef9a491fc2f1e13efb92058029c9536f870

immediate Git parent:
e0d2cda22a431c69a1b3eb4c650d79627d8aea40

PAR3 R3.2 checkpoint predecessor:
8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf

STREAM1 runtime code anchor:
8636a525c47b524e0ef597e46f37ffe6204d27ee

STREAM1 verification harness anchor:
e0d2cda22a431c69a1b3eb4c650d79627d8aea40
```

Важно: `PARENT` в git-смысле и архитектурный predecessor — разные понятия.
Непосредственный parent frozen verification HEAD — `e0d2cda...`.
PAR3 R3.2 `8ca0fcc...` и runtime anchor `8636a525...` подтверждены как
ancestors frozen HEAD.

## Exact Windows environment

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

fresh detached worktree:
C:\distributed-world-simulator\eco-stream1-r1-verify
```

## Verification result

```text
fresh detached worktree: PASS
import exit code:          0
source guards:             PASS
focused STREAM1:           PASS
exact comparisons:         108/108
transitive gate:           PASS (11/11)
final identity unchanged:  PASS
tracked worktree clean:    YES

VERDICT: PASS
```

Focused acceptance marker:

```text
STREAM1 exact generation comparisons: 108
ECO.EVO7 STREAM1 Bounded Generation Stream: PASS (195 assertions)
```

Transitive marker:

```text
ECO.EVO7 STREAM1 transitive acceptance: PASS
```

Transitive suite:

```text
LS3.3    PASS (47)
LS3.4    PASS (45)
PERF1    PASS (69)
PAR0     PASS (38)
PAR0.2   PASS (62; 30/30 hash)
PAR1     PASS (138; 224 exact)
PAR2     PASS (105; 108 exact)
PAR3     PASS (130; 108 exact)
STREAM1  PASS (195; 108 exact)
VIS3     PASS (107)
PLAY0    PASS (103)
```

## Source guards

Verified on frozen target:

- `LineageExtension.reproduce_bundle(`: PAR3 candidate kernel = 1, LS3.3 = 0;
- `var distance_m := inherited_distance`: STREAM1 route kernel = 1, LS3.3 = 0;
- canonical `recruitment_event_hash`: only PAR0 recruitment kernel;
- STREAM1 executor facade present through LS3.3 → LS3.4 → LS3.6 Workbench;
- `_validate_generation_evidence_values` executes before authoritative
  `generation = next_generation`.

## Import note

Import completed with exit code 0.

Three legacy scene parse diagnostics (`Expected '['`) were observed in:

- `eco_evo5_probe2_tree_lab.tscn`;
- `eco_evo5_t51_creature_lab.tscn`;
- `eco_evo5_terrain_fly_lab.tscn`.

They are classified as **pre-existing baseline condition**, not STREAM1
regression: the scenes are unchanged between the PAR3 R3.2 predecessor and the
frozen STREAM1 target, and the same diagnostics were present in earlier
accepted Windows verification environments.

This acceptance does not claim those legacy diagnostics are repaired.

## Acceptance conclusion

STREAM1 R1 satisfies its frozen acceptance gate:

```text
fresh exact-Windows verification
+
108/108 canonical serial↔STREAM1 parity
+
fail-closed fault coverage
+
11/11 transitive gate
+
immutable HEAD/TREE
+
clean tracked worktree
```

Therefore:

```text
ECO.EVO7 / STREAM1 R1 = ACCEPTED
```

The accepted runtime semantics remain:

- bounded deterministic generation proposal;
- no chunk-level authority;
- LS3.3-only atomic generation publication;
- chunk shape excluded from proposal identity;
- R1 transport remains in-process;
- no production/world/network authority promotion.

Remote/distributed transport remains a later checkpoint and must preserve the
same canonical proposal identity and authority boundary.
