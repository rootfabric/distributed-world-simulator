# ECO.EVO7 PERF2.4 R2 — Windows Exact Verification Instruction

Дата: 2026-08-31

Статус:

```text
VALIDATION ONLY
DO NOT MERGE
```

## Exact source subject

```text
branch:
feature/eco-evo7-perf2-4-runtime-optimization-r2

HEAD:
8c022eaea2dd6253b3fd27a84d3db3e88c51d5a3

parent R1 RED subject:
44210d55c657db31009dd98f0b714885366b5ae9

accepted PERF2.3 control tip:
4997f7116d0e4ac40ed88fe8a41a7b5029621d71

PERF2.0 contract blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

The R2 source delta from R1 is intentionally limited to:

```text
scripts/ecology/perf/eco_evo7_perf24_runtime_optimization_profiler_v1.gd

+10 / -0
```

The repair adds the missing canonical PERF2 helper:

```gdscript
func _stable_float_token(value) -> String:
    if not _finite_nonnegative(value):
        return "INVALID"
    return "%.6f" % float(value)
```

No thresholds, workload, runtime optimization math, report schema, frozen contract or biology are changed.

## Required Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Use native Windows double-Godot.

## Verification policy

Run from a fresh detached worktree on the exact source HEAD.

Do not modify files, commit, push, weaken thresholds or retry a true performance RED until it becomes green.

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
optimization_claim               TRUE
```

Serial crossover is not required.

## R1 RED that R2 must repair

The R1 exact Windows verifier found:

```text
Function "_stable_float_token()" not found in base self.
```

Call sites existed in the PERF2.4 profiler, but the helper definition was absent. PERF1 through PERF2.3 passed on the same frozen subject. The R2 verification must prove that the compile failure is gone and then execute the full A/B campaign.

## Verdict rules

```text
PASS
  all transitive gates green
  + 27/27 exact A/B parity
  + all frozen performance thresholds
  + report validates
  + final HEAD/TREE unchanged
  + tracked worktree clean

RED
  any correctness or performance requirement fails

BLOCKED
  infrastructure prevents a valid exact run
```

On RED, do not repair in the verification worktree.

On PASS, PERF2.4 may proceed to formal acceptance and PERF2.SIM closure.

On RED, PERF2.4 remains open and a new repair candidate is required.
