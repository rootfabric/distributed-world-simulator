# ECO.EVO7 PERF2.1 R1 — STREAM1 Generation Profiling

Дата: 2026-08-31  
Статус: **CODE COMPLETE / EXACT WINDOWS VERIFICATION REQUIRED**

## Predecessor

Accepted PERF2.0 frozen subject:

```text
HEAD:
5994598d317a55ddae2954f943021878a279afc9

TREE:
a0241f89b6fd7546a27e4388992ffe371b4c5de6

Godot:
4.7.1.stable.double.custom_build.a13da4feb
```

Formal acceptance control base:

```text
73317ce3c35a70a9f8e882e733f23539761027a8
```

Frozen measurement contract:

```text
path:
config/ecology/eco-evo7-perf2-measurement-contract.v1.json

revision:
ECO.EVO7-PERF2.0-R1

Git blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

PERF2.1 does not modify that file or protocol.

## Branch

```text
feature/eco-evo7-perf2-1-stream1-generation-profiling-r1
```

Implementation anchors before metadata-only freeze:

```text
profiler runtime head:
85b9e358dd2edc0213c37b6c5005569fb7f6f378

acceptance harness head:
314cacb607ba57e76986cea0b95c38fe1c2b81c8
```

Final branch HEAD/TREE must be resolved again by the independent Windows verifier.

## Goal

PERF2.1 measures accepted STREAM1 generation execution under the already
accepted PERF2.0 protocol.

It intentionally separates:

```text
PERF2.0 = how measurements are valid
PERF2.1 = what current STREAM1 actually measures
PERF2.2+ = memory/scaling/optimization evidence
```

This checkpoint does not optimize simulation code.

## New implementation

### Profiler

```text
scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd
```

The profiler:

- consumes `Contract.load_contract()`;
- refuses contract revision drift;
- uses public `Workbench.setup()`;
- uses public `Workbench.advance_generations(1)`;
- injects STREAM1 only through public `set_generation_stream_executor()`;
- uses the accepted PERF2 process-local Probe around the measured window;
- never calls LS3 private/core mutation paths;
- never implements candidate/reproduction/dispersal/recruitment biology;
- emits contract-valid measurement samples;
- builds p50/p95/mean/min/max through the accepted
  `Contract.summarize()` implementation;
- emits one machine-local, noncanonical profiling report.

## R1 Workbench envelope

The PERF2.0 protocol permits arbitrary deterministic seeds/initial population,
but the current public Workbench exposes these as frozen constants:

```text
FOUNDER_SEED
PLACEMENT_SEED
EVOLUTION_SEED
INITIAL_RECORDS
```

PERF2.1 R1 **does not expand Workbench** just to benchmark alternate values.

Instead it fail-closes if campaign config attempts to change them.

This is deliberate:

```text
benchmark convenience
must not
change simulator semantics
```

Environment recipe and environment seed remain supported through the existing
public Workbench spec.

## Focused campaign

R1 acceptance uses the minimum accepted PERF2.0 envelope:

```text
recipe:
MIXED_PHYSICAL_HETEROGENEITY

execution modes:
SERIAL_REFERENCE
STREAM1

warmup generations:
2

measured generations:
12

repetitions:
3

initial records:
64

STREAM1 parents_per_chunk:
64

audit interval:
10

audit generation 1:
true
```

Therefore focused runtime executes:

```text
1 recipe
× 2 execution modes
× 3 repetitions
× (2 warmup + 12 measured generations)
=
84 generation advances
```

The profiler supports multiple recipes; the other accepted recipes may be used
for later/full campaigns without changing the measurement contract.

## Sample timing semantics

Each repetition is one PERF2.0 measurement sample.

`wall_ms`:

```text
wall time of the entire 12-generation measured window
```

Stage timings:

```text
generation_total_ms
ls33_total_ms
stream_total_ms
candidate_build_ms
route_build_ms
recruitment_eval_ms
audit_ms
```

are arithmetic mean milliseconds per measured generation.

The accepted PERF2.0 summary logic then computes repetition-level:

```text
count
p50
p95
mean
min
max
```

PERF2.1 does not redefine the percentile rule.

## STREAM1 measured-window telemetry

Warmup telemetry is fenced out.

Immediately after warmup the profiler snapshots STREAM1 counters.

The final report contains measured-window deltas for:

```text
stream_calls
chunks_processed
serial_audit_calls
oracle_elided_generations
```

For the accepted 12-generation measured window:

```text
stream_calls == 12
```

is an acceptance assertion.

The report also records:

```text
chunk_count
max_parent_chunk
max_candidate_chunk
```

and verifies the accepted R1 bounds:

```text
max_parent_chunk <= 64
max_candidate_chunk <= 128
```

## SERIAL_REFERENCE semantics

SERIAL_REFERENCE uses the same Workbench and physical simulation load without
injecting STREAM1.

Its contract sample still contains all required PERF2.0 metric fields.

STREAM1-specific fields are explicit zeros:

```text
stream_total_ms = 0
audit_ms = 0
stream_calls = 0
chunks_processed = 0
serial_audit_calls = 0
oracle_elided_generations = 0
```

This is not interpreted as a STREAM1 speed measurement for SERIAL; it is an
explicit not-applicable representation inside the already frozen sample schema.

## Cross-mode correctness fence

For each of the 3 repetition pairs:

```text
SERIAL_REFERENCE
↕
STREAM1
```

PERF2.1 requires:

```text
exact workload_hash:
different
```

because execution backends differ.

But:

```text
simulation_workload_hash:
identical
```

and:

```text
final_workbench_hash
final_ecology_state_hash
final_population_hash
final_classification_hash
```

must all be exact identical.

The focused marker is:

```text
PERF2.1 cross-mode exact result pairs: 3/3
```

Any mismatch aborts report creation.

## Report artifact

Focused acceptance writes:

```text
artifacts/perf2/perf2-1-generation-profile-focused.json
```

The artifact is ignored by Git.

Report identity:

```text
schema:
distributed_world_simulator.ecology.evo7_perf2_1.generation_profile.v1

revision:
ECO.EVO7-PERF2.1-R1
```

It binds:

- exact HEAD;
- exact TREE;
- exact Godot version;
- host fingerprint;
- accepted PERF2.0 revision;
- accepted PERF2.0 Git blob;
- campaign config;
- all raw contract-valid samples;
- all summaries;
- non-authoritative flags;
- report evidence hash.

The report is:

```text
NONCANONICAL
MACHINE_LOCAL
SIDE_CHANNEL_ONLY
MEASUREMENT_ONLY
```

It is not persistence/world/network truth.

## Required summaries

Focused R1 builds 12 summary rows:

```text
2 modes
×
6 metrics
```

Metrics:

```text
generation_total_ms
ls33_total_ms
candidate_build_ms
route_build_ms
recruitment_eval_ms
audit_ms
```

Each summary uses all three passing repetitions.

The test prints evidence lines:

```text
PERF2.1 PROFILE recipe=... mode=... metric=... count=3 p50=... p95=... mean=...
```

This allows the exact Windows log to become the first real generation-profile
baseline without making a generalized speedup claim.

## Acceptance test

Added:

```text
tests/ecology/eco_evo7_perf21_generation_profiling_acceptance.gd
```

It proves:

1. exact HEAD/TREE/host are supplied by the runner;
2. PERF2.0 contract validates;
3. PERF2.0 revision remains frozen;
4. default campaign satisfies accepted minimums;
5. unsupported Workbench seed changes fail closed;
6. real Earth campaign completes;
7. all 6 samples validate against PERF2.0;
8. 3 serial + 3 STREAM1 repetitions are present;
9. all timing fields are finite/nonnegative;
10. all count fields are valid;
11. measured-window STREAM1 calls are exactly 12;
12. working-set chunk bounds remain intact;
13. 3/3 SERIAL↔STREAM1 pairs have exact canonical parity;
14. all 12 p50/p95 summaries validate;
15. report JSON writes/parses and preserves report hash;
16. profiler owns no private ecology/biology authority;
17. canonical Workbench source remains PERF2.1-free.

Expected focused marker:

```text
ECO.EVO7 PERF2.1 STREAM1 Generation Profiling: PASS
```

## Transitive runner

Added:

```text
RUN_ECO_EVO7_PERF2_1_TESTS.ps1
```

Canonical repository-local entrypoint:

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.1 -GodotPath <exact-Godot>
```

The transitive order is:

```text
PERF1
→ STREAM1
→ PERF2.0
→ PERF2.1
```

The runner also verifies the accepted PERF2.0 contract Git blob before any
runtime measurement.

Expected final marker:

```text
ECO.EVO7 PERF2.1 transitive generation-profiling acceptance: PASS
```

## No optimization claim

PERF2.1 may report factual host/workload-bound numbers such as:

```text
STREAM1 generation_total_ms p50 = ...
SERIAL_REFERENCE ls33_total_ms p95 = ...
candidate_build is the largest observed measured stage in this campaign
```

PERF2.1 does not yet prove:

- general STREAM1 speedup;
- production scalability;
- memory improvement;
- best worker count;
- accepted optimization;
- PLAY1 readiness.

Those remain later gates.

## Scope diff

Relative to acceptance control base, the runtime/test implementation changes
only:

```text
scripts/ecology/perf/eco_evo7_perf21_generation_profiler_v1.gd
tests/ecology/eco_evo7_perf21_generation_profiling_acceptance.gd
RUN_ECO_EVO7_PERF2_1_TESTS.ps1
RUN_ECO_TEST_WORKFLOW.ps1
```

No LS3/Workbench/STREAM1 biology/runtime file is modified.

The accepted PERF2.0 JSON and implementation are not modified.

## Acceptance condition

Implementer does not self-accept PERF2.1.

Formal acceptance requires fresh exact Windows verification:

```text
fresh detached worktree
+
exact frozen HEAD/TREE
+
Godot 4.7.1.stable.double.custom_build.a13da4feb
+
accepted PERF2.0 contract blob unchanged
+
PERF1 PASS
+
STREAM1 PASS
+
PERF2.0 PASS
+
PERF2.1 focused PASS
+
3/3 exact cross-mode pairs
+
12 valid summary rows
+
transitive marker PASS
+
tracked worktree clean
```

Until then:

```text
PERF2.1 R1
CODE COMPLETE
AWAITING EXACT WINDOWS
NOT ACCEPTED
```
