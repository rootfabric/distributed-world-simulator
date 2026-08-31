# ECO.EVO7 PERF2.1 R2 — STREAM1 Generation Profiling

Дата: 2026-08-31  
Статус: **IMPLEMENTATION CANDIDATE / EXACT WINDOWS CLOSURE REQUIRED**

## Predecessor

Accepted PERF2.0 control tip:

```text
07bffc0e7f30bac4479f1b7e53dee3fee3a818f6
```

Accepted measured implementation subject:

```text
5994598d317a55ddae2954f943021878a279afc9
```

Frozen measurement contract:

```text
revision
ECO.EVO7-PERF2.0-R1

Git blob
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

PERF2.1 may not mutate that contract or accepted STREAM1/ecology runtime.

## Goal

Produce the first repeatable generation-level comparison matrix under PERF2.0.

PERF2.1 answers:

- what one measured generation costs under serial reference;
- what STREAM1 costs at bounded chunk sizes 1 / 7 / 64;
- where time is spent inside LS3.3;
- how much audit work remains;
- whether exact canonical ecology remains identical;
- which execution configuration is the best input for PERF2.2/2.3 investigation.

It does **not** optimize runtime.

## Frozen campaign

One physical recipe:

```text
MIXED_PHYSICAL_HETEROGENEITY
```

Four execution configurations:

```text
SERIAL_REFERENCE
STREAM1_CHUNK_1
STREAM1_CHUNK_7
STREAM1_CHUNK_64
```

Each configuration:

```text
warmup generations     2
measured generations  12
repetitions            3
```

Total generation advances:

```text
4 configs × 3 repetitions × (2 + 12)
= 168 generation advances
```

Total PERF2 samples:

```text
12
```

## Hidden-context hardening

PERF2.0 workload identity intentionally remains frozen and is not modified.

PERF2.1 adds a stricter campaign-level context identity for fixed Workbench semantics that
must not drift invisibly:

```text
planet_source_kind = PROCEDURAL_EARTH_WORLD
world_seed         = Workbench.DEFAULT_WORLD_SEED
competition        = enabled
grid_size          = Workbench.GRID_SIZE
cell_size_m        = Workbench.CELL_SIZE_M
```

These values produce:

```text
campaign_context_hash
```

Every sample and the top-level report bind this hash.

Therefore changing world seed, competition mode, grid or cell size cannot silently reuse
the same PERF2.1 evidence set.

## Runtime boundary

PERF2.1 code may call only:

```text
Workbench.setup(...)
Workbench.advance_generations(...)
Workbench.set_generation_stream_executor(...)
public profile/snapshot getters
```

Forbidden:

- private ecology core access;
- record/population assignment;
- candidate/recruitment backend replacement;
- biology seed generation;
- mutation/dispersal identity changes;
- canonical snapshot changes;
- persistence/network/world writes.

Protected runtime diff guard requires no changes relative to accepted PERF2.0 base under:

```text
scripts/ecology/shadow/**
eco_evo7_stream1_generation_stream_executor_v1.gd
eco_evo7_stream1_route_kernel_v1.gd
eco_evo7_perf2_measurement_contract_v1.gd
eco_evo7_perf2_measurement_probe_v1.gd
```

Only the new profiling layer may change.

## Timing semantics

All required sample timings are **mean per measured generation**:

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

The full 12-generation measured window wall time is additionally retained as diagnostic
evidence under:

```text
metrics.window.total_wall_ms
```

This removes the R1 ambiguity where wall time was a whole-window total while stage timings
were per-generation means.

## Working-set semantics

SERIAL_REFERENCE is represented honestly as one monolithic working set:

```text
chunk_count = 1
max_parent_chunk    = measured full parent set
max_candidate_chunk = measured full candidate set
```

STREAM1 records measured-window maxima and must satisfy:

```text
max_parent_chunk <= configured chunk size
max_candidate_chunk <= configured chunk size × offspring_per_parent
```

For the frozen 12-generation measured window after warmup:

```text
stream_calls              = 12
serial_audit_calls        = 1
oracle_elided_generations = 11
```

The one measured audit is generation 10.

## Canonical parity

For each repetition the same serial result is compared against chunk sizes 1, 7 and 64:

```text
3 repetitions × 3 STREAM1 configs
= 9 exact cross-configuration pairs
```

Each pair must satisfy exact equality of:

```text
workbench_hash
ecology_state_hash
population_hash
classification_hash
```

Required:

```text
9 / 9 exact
```

A timing improvement with any canonical divergence is invalid evidence.

## Statistics

For every configuration and every required metric:

```text
count = 3
p50
p95
mean
min
max
```

Matrix:

```text
4 configurations × 8 metrics
= 32 summary rows
```

## Diagnostic execution ratios

The report emits three serial-to-STREAM1 comparisons:

```text
chunk 1
chunk 7
chunk 64
```

Each includes:

```text
observed_wall_ratio_serial_over_stream
observed_generation_ratio_serial_over_stream
exact_pairs = 3
optimization_claim = false
```

Ratio > 1 means the STREAM1 configuration was faster in that measurement set.

It is still **not** an accepted optimization.

## Artifact

Machine-local report:

```text
artifacts/perf2/perf2-1-generation-profile-r2.json
```

Top-level schema is the accepted generic PERF2 report schema:

```text
distributed_world_simulator.ecology.evo7_perf2.measurement_report.v1
```

Subtype:

```text
distributed_world_simulator.ecology.evo7_perf2_1.generation_profile.v2
```

The report hash binds:

- exact target HEAD/TREE;
- exact Godot;
- hashed host fingerprint;
- frozen PERF2.0 contract blob;
- campaign context hash;
- raw sample timings/counts/memory/STREAM1 telemetry;
- all 32 summaries;
- all 3 observed comparison rows.

## Transitive runner

Canonical entrypoint:

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.1 -GodotPath <exact-double>
```

It executes:

```text
PERF1
→ STREAM1
→ PERF2.0
→ PERF2.1 R2
```

and then independently validates the JSON artifact and tracked-tree cleanliness.

Expected marker:

```text
ECO.EVO7 PERF2.1 transitive generation-profiling R2 acceptance: PASS
```

## Acceptance

PERF2.1 R2 may be accepted only when one immutable HEAD has:

```text
exact Godot                         PASS
fresh import                        PASS
protected runtime diff              PASS
PERF1                               PASS 69
STREAM1                             PASS 195 / 108 exact
PERF2.0                             PASS 62
PERF2.1 R2                          PASS
cross-configuration parity          9/9
samples                             12
summaries                           32
comparisons                         3
artifact roundtrip/hash             PASS
canonical repository workflow       PASS
tracked tree                        clean
Project Control                     PASS
exact Windows CI closure            SUCCESS
```

Until then:

```text
PERF2.1 = IMPLEMENTATION CANDIDATE
PERF2.2 = BLOCKED
```


## Repair note — JSON round-trip numeric normalization

Independent Ubuntu verification of exact candidate
`2ec97b13101edf0f27bd5fe5b62700893dd25ffd` proved all 12 samples,
9/9 cross-configuration canonical pairs and profiling ratios, but found the artifact
round-trip validator was not tolerant of Godot JSON numeric coercion.

Godot `JSON.parse_string` materialized integral JSON numbers as floating-point Variant
values in parsed config/context/sample structures. Strict Variant comparisons therefore
rejected semantically identical evidence after write → parse.

Repair policy:

```text
7      accepted as integer
7.0    accepted as integer-equivalent JSON value
7.5    rejected
"7"    rejected
```

PERF2.0 remains frozen. PERF2.1 now creates a contract-compatible normalized validation
view for integral workload/count/memory/telemetry fields while leaving the raw JSON
artifact and measured values unchanged.

The report hash uses the same normalized contract view so in-memory and parsed artifacts
produce identical evidence identity.

The accepted STREAM1 regression emits two canonical markers:

```text
STREAM1 exact generation comparisons: 108
ECO.EVO7 STREAM1 Bounded Generation Stream: PASS (195 assertions)
```

Verification must check these two markers independently; no combined
`PASS (195 assertions, 108 comparisons)` line is required.


## Repair note — JSON float hash stability

The second independent Ubuntu verification of exact candidate
`a0ce7de334a09fe16a89976a1aa57eec9a56afa1` proved that config/context numeric
normalization was fixed, but the parsed artifact still failed the final full report
validation.

The remaining boundary was the recomputed evidence hash: raw timing, summary and ratio
floats were formatted with 12 decimal places. Godot JSON serialization may preserve the
semantic measurement while restoring a slightly different final binary mantissa; the
stored report_hash string therefore survived, while recomputing it from the parsed
artifact could differ.

PERF2.1 now canonicalizes float evidence tokens to six decimal places in milliseconds /
ratio space. This is substantially finer than the microsecond-resolution source clock
while removing meaningless JSON binary-float tail sensitivity.

Tamper detection remains fail-closed: the acceptance test changes
`generation_total_ms` by `+0.001 ms` (one microsecond) and requires the parsed report
to become invalid.

The acceptance test now distinguishes:

```text
stored report_hash preserved                    PASS
recomputed report_hash after JSON round-trip    PASS
full parsed report validation                   PASS
one-microsecond timing tamper                    REJECT
```
