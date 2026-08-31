# ECO.EVO7 PERF2.4 R3 — Windows Exact Verification Instruction

Дата: 2026-09-01

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact source subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r3

HEAD:
df257dc0b717a898b2a92f77d73997f797be801d

TREE:
a788bc574f930695666bcaba1f984c2dbe50baa4

parent R2 RED:
8c022eaea2dd6253b3fd27a84d3db3e88c51d5a3

accepted PERF2.3 control tip:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## R2 exact Windows RED evidence

```text
54/54 samples
9/9 comparison points
27/27 exact legacy<->optimized pairs
bounded working set PRESERVED
deterministic operation reduction PROVEN

wall geomean speedup:
1.016056 < 1.02

STREAM1 geomean speedup:
1.012797 < 1.03

improved wall points:
7/9

non-regressed wall points:
9/9

minimum point wall ratio:
0.991301 >= 0.97

optimization_claim:
FALSE
```

R2 was a true PERFORMANCE THRESHOLD FAILURE, not correctness or infrastructure failure.

## R3 repair scope

R3 changes optimized orchestration only:

1. if the incoming parent records are already canonical by record_id, avoid a redundant full parent sort; if they are not ordered, fall back to the canonical sorter;
2. replace three independent full-generation candidate_hash sorts with one aligned index permutation shared by candidates, routes and recruitment;
3. legacy baseline behavior remains unchanged;
4. optimized telemetry now reports one generation-boundary sort per generation instead of three.

Frozen thresholds, workload, hashes, biology and report contract are unchanged.

## Required Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Use native Windows double-Godot.

## Required exact campaign

Run from a fresh detached worktree on the source HEAD.

Required transitive gates:

```text
fresh import
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3
PERF2.4
```

Required PERF2.4 evidence:

```text
samples                          54
comparison points                 9
legacy<->optimized exact pairs   27/27
bounded working set              PRESERVED
operation reduction              PROVEN
wall geomean speedup             >= 1.02
STREAM1 geomean speedup          >= 1.03
improved wall points             >= 6/9
non-regressed wall points        9/9
minimum point wall ratio         >= 0.97
optimization_claim               TRUE
```

Do not weaken thresholds. Do not retry a true performance RED to fish for better timing. Do not modify code in the verification worktree.

On PASS, PERF2.4 may proceed to formal acceptance and PERF2.SIM closure.

On RED, PERF2.4 stays open and the exact failing metrics must be returned for the next repair.
