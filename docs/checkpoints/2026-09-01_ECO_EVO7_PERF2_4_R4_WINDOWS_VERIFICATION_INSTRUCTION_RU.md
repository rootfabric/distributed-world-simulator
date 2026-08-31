# ECO.EVO7 PERF2.4 R4 — Windows Exact Verification Instruction

Дата: 2026-09-01

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact source subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r4

HEAD:
c81e6efb4460e6aa8ea743df9d0ca9651e42bea3

TREE:
e9f207e856b42c5301ac65130200d193bc6dcde0

base R2 exact subject:
8c022eaea2dd6253b3fd27a84d3db3e88c51d5a3

rejected R3 subject:
df257dc0b717a898b2a92f77d73997f797be801d

accepted PERF2.3 control tip:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Why R4 branches from R2

R3 exact Windows verification regressed relative to R2:

```text
R2 wall geomean      1.016056
R3 wall geomean      1.001754

R2 STREAM1 geomean   1.012797
R3 STREAM1 geomean   1.004387
```

R3's aligned permutation/boundary-sort experiment is therefore not carried forward.

## R4 repair scope

R4 changes optimized orchestration only.

The optimized per-chunk path no longer allocates and copies:

```text
ordered.slice(...) transient chunk array
per-chunk candidates array
per-chunk routes array
per-chunk recruitment array
three append_array copies into generation arrays
```

Instead, the same accepted pure kernels append their exact results directly to the full generation proposal arrays over the bounded cursor range:

```text
CandidateKernel.build_candidate
RouteKernel.build_route
RecruitmentKernel.evaluate_recruitment_event
RecruitmentKernel.recruitment_event_hash
```

Legacy baseline behavior is unchanged.

Generation-boundary canonicalization stays at the R2 form: three explicit canonical sorts.

No biology formula, candidate/route/recruitment hash semantic, frozen PERF2.0 contract, workload, report schema, threshold or authority is changed.

## Required Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Use native Windows double-Godot.

## Required campaign

Fresh detached worktree on exact source HEAD.

Required gates:

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

Do not weaken thresholds.
Do not repair code in the verification worktree.
Do not retry a genuine performance RED to fish for better timing.

If R4 receives correctness RED, return the exact first failure.
If R4 completes the campaign but misses performance gates, return all nine profile points and the summary.
