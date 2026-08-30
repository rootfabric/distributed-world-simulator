# ECO.EVO7 PERF2.0 R1 — Measurement Contract

Дата: 2026-08-30  
Статус: **IMPLEMENTATION CANDIDATE / EXACT DOUBLE-GODOT VERIFICATION REQUIRED**

## Predecessor

Accepted STREAM1 R1 subject:

```text
HEAD  4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4
TREE  68389ef9a491fc2f1e13efb92058029c9536f870
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Control/metadata successor base:

```text
843f503e2ff2bf4c8e38a8707380dae17088aff8
```

PERF2.0 starts the simulation-side PERF2 lane. It does not wait for VIS4 / PLAY0.MORPH.

## Goal

Freeze one measurement protocol before PERF2.1–PERF2.4 produce performance claims.

Without PERF2.0, two optimization runs could accidentally differ in seeds, chunk size,
warmup, Godot build, host, memory semantics or reporting statistic while still being
presented as a speedup.

PERF2.0 makes those differences explicit and fail-closed.

## New contract surfaces

```text
config/ecology/eco-evo7-perf2-measurement-contract.v1.json
scripts/ecology/perf/eco_evo7_perf2_measurement_contract_v1.gd
scripts/ecology/perf/eco_evo7_perf2_measurement_probe_v1.gd
tests/ecology/eco_evo7_perf2_measurement_contract_acceptance.gd
RUN_ECO_EVO7_PERF2_0_TESTS.ps1
RUN_ECO_EVO7_PERF2_0_TESTS.sh
```

## Authority boundary

PERF2 measurements are:

```text
NONCANONICAL
SIDE-CHANNEL ONLY
MEASUREMENT ONLY
```

They MUST NOT:

- enter ecology/workbench hashes;
- change candidate / route / recruitment identity;
- change generation publication;
- change STREAM1 chunk/proposal semantics;
- become persistence/network/world truth;
- modify biology to improve a benchmark.

The measurement validator has no ecology execution method.
The process probe references only OS/time process state and has no Workbench/LS authority reference.

## Workload identity

A comparable workload is frozen by these fields:

```text
workload_id
execution_mode
environment_recipe
warmup_generations
measured_generations
repetitions
initial_records
parents_per_chunk
audit_interval_generations
audit_generation_1
founder_seed
placement_seed
evolution_seed
environment_seed
```

Default STREAM1 measurement envelope:

```text
warmup_generations     2
measured_generations  12
repetitions            3
initial_records       64
parents_per_chunk     64
audit_interval        10
audit_generation_1   true
```

Minimum evidence for a performance claim:

```text
warmup >= 1
measured generations >= 12
repetitions >= 3
```

A deterministic `workload_hash` is derived only from controlled workload fields.

## Comparison identity

A before/after optimization comparison key includes:

```text
workload_hash
exact Godot version
host_fingerprint
measurement_method_revision
```

It intentionally excludes:

```text
target HEAD/TREE
run id
timings
memory values
```

Why target SHA is excluded: a valid optimization comparison necessarily compares different
source revisions. Both SHAs are still recorded in each sample; they simply do not make the
pair incomparable.

Why host is included: a result from another machine is useful evidence but cannot silently
be merged into the same before/after performance claim.

## Correctness gate

Performance improvement is invalid unless both sides produce exactly the same canonical
result fingerprint.

Required final hashes:

```text
workbench_hash
ecology_state_hash
population_hash
classification_hash
```

Therefore:

```text
faster + different ecology = FAIL
slower + same ecology      = valid measurement
faster + same ecology      = candidate optimization evidence
```

## Timing semantics

Unit: milliseconds.

Required fields:

```text
wall_ms
generation_total_ms
ls33_total_ms
stream_total_ms
candidate_build_ms
route_build_ms
recruitment_eval_ms
audit_ms
```

Existing PERF1 and STREAM1 timing surfaces remain the measurement sources.
PERF2.0 does not duplicate those calculations.

## Count / bounded-working-set semantics

Required counts:

```text
generation
population
parent_count
candidate_count
chunk_count
max_parent_chunk
max_candidate_chunk
```

STREAM1 executor telemetry additionally records:

```text
stream_calls
chunks_processed
serial_audit_calls
oracle_elided_generations
```

These allow PERF2.1/2.2 to distinguish real speedup from accidentally processing less work.

## Memory semantics

PERF2 separates engine allocator observations from operating-system process RSS.

Built-in probe:

```text
engine_static_bytes
engine_static_peak_bytes
```

Optional external sampler:

```text
process_rss_bytes
process_peak_rss_bytes
```

The latter remain explicit `null` until a platform runner supplies them.

This prevents calling Godot static allocator usage "process RSS".

## Statistics

Every comparable repetition set reports:

```text
count
p50
p95
mean
min
max
```

p50/p95 use the frozen linear-interpolation percentile rule.

`min` and `max` are diagnostics only.

Forbidden:

```text
best-of-N as primary result
discarding slow passing runs without declared reason
including failed runs in speedup claims
mixing different comparison_key values
```

## PERF2.0 acceptance

Focused acceptance proves:

1. contract JSON loads and validates;
2. workload hash is insertion-order invariant;
3. changing controlled workload changes workload hash;
4. timing changes do not change comparison identity;
5. target SHA changes do not change comparison identity;
6. host changes do change comparison identity;
7. negative/invalid measurements fail closed;
8. canonical result divergence blocks comparison;
9. failed runs are excluded;
10. 3-run p50/p95/mean summary is deterministic;
11. process-local probe captures wall/static-memory side-channel values;
12. one real Workbench STREAM1 generation remains byte/hash-equivalent to the serial oracle;
13. existing PERF1/STREAM1 timings and bounded telemetry are available without new biology instrumentation;
14. contract/probe own no ecology truth.

Transitive runner:

```text
PERF1
→ STREAM1
→ PERF2.0
```

Expected final marker:

```text
ECO.EVO7 PERF2.0 transitive measurement-contract acceptance: PASS
```

## Scope intentionally deferred

PERF2.0 does NOT yet claim:

- STREAM1 speedup;
- memory improvement;
- large-scale population performance;
- an optimization;
- VIS4/PLAY0.MORPH performance;
- PLAY1 readiness.

Those belong to:

```text
PERF2.1 STREAM1 Generation Profiling
PERF2.2 Working-set / Memory
PERF2.3 Simulation Scaling
PERF2.4 Runtime Optimization
        ↓
PERF2.CONV (after PLAY0.MORPH)
```

## Acceptance condition

PERF2.0 may be marked accepted only after an exact double-Godot run on a frozen branch HEAD:

```text
exact Godot PASS
PERF1 regression PASS
STREAM1 regression PASS
PERF2.0 focused PASS
transitive runner PASS
tracked worktree clean
exact HEAD/TREE recorded
```

Until then:

```text
PERF2.0 = IMPLEMENTATION CANDIDATE
PERF2.1 = BLOCKED WAIT PERF2.0 ACCEPTANCE
```
