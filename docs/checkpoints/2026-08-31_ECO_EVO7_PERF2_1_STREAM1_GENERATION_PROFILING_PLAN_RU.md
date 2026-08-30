# ECO.EVO7 PERF2.1 R1 — STREAM1 Generation Profiling Plan

Статус: **AUTHORIZED / NOT STARTED**.

## Predecessor

Accepted PERF2.0 subject:

```text
HEAD:
5994598d317a55ddae2954f943021878a279afc9

TREE:
a0241f89b6fd7546a27e4388992ffe371b4c5de6

Godot:
4.7.1.stable.double.custom_build.a13da4feb
```

Acceptance evidence:

`docs/checkpoints/2026-08-31_ECO_EVO7_PERF2_0_R1_ACCEPTED_RU.md`

Frozen measurement contract:

```text
config/ecology/eco-evo7-perf2-measurement-contract.v1.json
revision: ECO.EVO7-PERF2.0-R1
```

PERF2.1 MUST consume this contract unchanged.

## Goal

Produce a reproducible performance baseline for accepted STREAM1 generation
execution before PERF2.2 memory work and before any PERF2.4 optimization.

PERF2.1 answers:

```text
where does one measured generation spend time?
how stable are those timings across repetitions?
how does STREAM1 compare with SERIAL_REFERENCE on the same simulation load?
which stage is the dominant measured cost?
how much bounded-stream/audit overhead is observed?
```

It does **not** answer yet:

```text
what code should be optimized?
what speedup claim is accepted?
what memory reduction is accepted?
what production scaling target is satisfied?
```

## Hard rule

```text
MEASURE FIRST
OPTIMIZE LATER
```

PERF2.1 may add measurement/reporting orchestration and tests.

It MUST NOT change:

- candidate biology;
- route biology;
- recruitment biology;
- STREAM1 proposal identity;
- LS3.3 commit semantics;
- Workbench/ecology canonical hashes;
- accepted PERF2.0 measurement protocol;
- worker backend selection;
- chunk semantics to manufacture a faster result.

## Required baseline workloads

R1 minimum baseline uses the accepted contract envelope:

```text
warmup_generations:     2
measured_generations:  12
repetitions:            3
initial_records:       64
parents_per_chunk:     64
audit_interval:        10
audit_generation_1:   true
```

Execution modes:

```text
SERIAL_REFERENCE
STREAM1
```

Minimum recipe:

```text
MIXED_PHYSICAL_HETEROGENEITY
```

Recommended complete R1 profiling matrix:

```text
MIXED_PHYSICAL_HETEROGENEITY
WATER_GRADIENT_STRONG
RELIEF_DRAINAGE_STRONG
×
SERIAL_REFERENCE
STREAM1
×
3 repetitions
```

Every SERIAL_REFERENCE ↔ STREAM1 pair must have the same
`simulation_workload_hash` and exact canonical result parity.

## Required measurements

Reuse existing PERF1 / STREAM1 timing sources.

Required generation timing fields:

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

Also collect:

```text
population
parent_count
candidate_count
chunk_count
max_parent_chunk
max_candidate_chunk
stream_calls
chunks_processed
serial_audit_calls
oracle_elided_generations
```

No second biological profiler is allowed.

## Required summaries

For each comparable repetition group:

```text
count
p50
p95
mean
min
max
```

Primary reporting:

```text
generation_total_ms p50/p95
ls33_total_ms p50/p95
candidate_build_ms p50/p95
route_build_ms p50/p95
recruitment_eval_ms p50/p95
audit_ms p50/p95
```

Derived diagnostics may include percentage-of-generation breakdowns, but raw
timings remain authoritative measurement evidence.

## Correctness fence

No profiling row is valid unless:

```text
final_workbench_hash
final_ecology_state_hash
final_population_hash
final_classification_hash
```

remain exact between comparable SERIAL_REFERENCE and STREAM1 executions.

If timing is better but canonical result differs:

```text
PROFILE INVALID
```

## Artifact model

PERF2.1 may introduce a machine-local report:

```text
artifacts/perf2/perf2-1-generation-profile-<run-id>.json
```

The report is:

```text
NONCANONICAL
MACHINE_LOCAL
SIDE_CHANNEL_ONLY
```

It must bind:

- exact HEAD/TREE;
- exact Godot version;
- host fingerprint;
- accepted measurement-method revision;
- workload hash;
- simulation workload hash;
- raw samples;
- summary groups;
- canonical-result fingerprints.

The report must not enter world/ecology/persistence/network truth.

## Acceptance criteria

PERF2.1 R1 is complete only when a fresh exact-Windows gate proves:

1. accepted PERF2.0 regression remains GREEN;
2. measurement contract bytes/revision are unchanged;
3. SERIAL_REFERENCE profiles satisfy minimum warmup/measured/repetition rules;
4. STREAM1 profiles satisfy the same rules;
5. cross-mode pairs share `simulation_workload_hash`;
6. cross-mode pairs have exact canonical result parity;
7. all required timing/count/stream fields are present and finite/nonnegative;
8. p50/p95 summaries validate against PERF2.0 frozen interpolation;
9. no failed run is included in a performance summary;
10. report source owns no ecology authority;
11. exact HEAD/TREE remain unchanged;
12. tracked worktree is clean.

Expected focused marker:

```text
ECO.EVO7 PERF2.1 STREAM1 Generation Profiling: PASS
```

Expected transitive order:

```text
PERF2.0
→ PERF2.1
```

PERF1 and STREAM1 may remain inside the PERF2.0 predecessor gate rather than
being redundantly reimplemented.

## What PERF2.1 may conclude

Allowed:

```text
"under this frozen workload and host, stage X dominates measured generation time"
"STREAM1 p50/p95 is Y under this exact workload"
"SERIAL_REFERENCE and STREAM1 produce exact canonical parity"
"audit overhead is measured as Z"
```

Not allowed:

```text
"STREAM1 is generally N× faster"
"the simulator scales to production"
"memory is solved"
"optimization X is accepted"
```

Those stronger claims belong to later checkpoints with their own evidence.

## Next gate

On PERF2.1 acceptance:

```text
PERF2.2 — Working-set / Memory
```

becomes unblocked.

PERF2.4 Runtime Optimization remains blocked behind the profiling/scaling
sequence so optimization decisions are evidence-driven rather than guessed.
