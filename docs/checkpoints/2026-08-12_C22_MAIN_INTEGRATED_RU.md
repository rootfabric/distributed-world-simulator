# C22 — MAIN_INTEGRATED

**Date:** 2026-08-12  
**Decision:** `C22 MAIN_INTEGRATED`  
**Harness result:** `H0_1_PASS`  
**Architecture during integration:** `GLOBAL-P0-2026-08-10-R2`

## Human-authorized landing

The user explicitly authorized:

```text
HUMAN C22_RUNTIME_MERGE
WHOLE PR #90
NORMAL MERGE COMMIT
```

Pre-merge fence:

```text
main:                 4a42c2fb6befb386f5c3eb48d9ba070745e25bbb
PR #90 head:          ab674669b9a293d898e5ca5983b4918cc685d990
implementation head:  4c69de50c8374112d82efee2fd6917c770b3eae0
mergeable:            true
Project Control:      NON_RED
critical overlap:     0
C22 critical hits:    0
surface classes:      approved 4 classes only
BRANCH_LOCAL_CONTROL: 0
DO_NOT_LAND:          0
```

PR #90 was marked Ready only as part of the authorized operation and merged with a normal merge commit:

```text
eefd75fa3badec10c6e7db959e2a3992dba30f0e
```

Parents:

```text
4a42c2fb6befb386f5c3eb48d9ba070745e25bbb
ab674669b9a293d898e5ca5983b4918cc685d990
```

## Provenance and exact-tree fence

The accepted implementation commit remains an ancestor of canonical main:

```text
4c69de50c8374112d82efee2fd6917c770b3eae0
```

The merge commit and accepted PR head have the same tree:

```text
10c92456537efca220a0d9ae242a58f5dbfd2b74
```

Therefore the normal merge preserved the accepted runtime/test content byte-for-byte and changed only Git ancestry/provenance.

Accepted R8 evidence on the unchanged tree includes:

```text
pinned Harness                         13 / 13 PASS
C22 incremental local rebuild          28 assertions PASS
C22 compiled proxy graphical           35 assertions PASS
C24 proxy mesh backend contracts       81 assertions PASS
focused total                          144 / 0 failures
full world/core regression byte fence  PASS
Evidence Map                           PASS
Independent Reviewer                   PASS
Independent Verifier                   PASS
```

No claim is made that those Godot suites were rerun after the merge commit. Their applicability is preserved by exact tree identity; the mandatory new post-merge control proof was run separately on canonical main.

## Mandatory post-merge Project Control

GitHub Actions on exact merged main:

```text
run:                  31558679306
head:                 eefd75fa3badec10c6e7db959e2a3992dba30f0e
conclusion:           SUCCESS
standard PC0:         YELLOW / NON_RED
directional PC0:      YELLOW / NON_RED
cross-branch overlap: 0
C22 critical hits:    0
```

Directional watches remain:

```text
G  -> ECO   advisory / global_blocking=false
CH -> NX    future NX gate / global_blocking=true
```

`CH -> NX` does not reopen C22. It must be freshly revalidated before future H0.2/NX.C1 source acceptance.

## Canonical transition

All C22 integration predicates are satisfied:

```text
C22 MAIN_INTEGRATED
H0.1 runtime slot RELEASED
```

The old C22 source/convergence branch is evidence only and is no longer canonical runtime authority.

Next critical path:

```text
GLOBAL-P0 R3 exact-current-main refresh
→ final R3 verification
→ HUMAN GLOBAL_ARCHITECTURE_PROMOTION
```

Do not start H0.2/NX.C1 runtime before canonical R3 promotion and mandatory post-R3 PC0.
