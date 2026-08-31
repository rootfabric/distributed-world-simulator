# ECO.EVO7 PERF2.2 R1 — Working-set / Memory

Дата: 2026-08-31

Статус:

```text
IMPLEMENTATION CANDIDATE
ONE EXACT LOCAL PASS REQUIRED
UBUNTU OR WINDOWS
```

Predecessor:

```text
PERF2.1 R2 ACCEPTED
exact tested HEAD:
fccf4f99fd3c257abf90c37e584b965e2cddfa6a

accepted control tip:
7044c13e8cd9b036f318192ba0d62c6f3393fb60
```

Frozen measurement contract:

```text
ECO.EVO7-PERF2.0-R1

blob:
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Goal

PERF2.2 answers two different questions without conflating them:

1. How much structural record pressure does STREAM1 bound compared with the monolithic serial path?
2. What process-local allocator memory telemetry accompanies those executions?

These are deliberately separate evidence classes.

PERF2.2 does not optimize runtime.

## Input

PERF2.2 consumes only a fully validated PERF2.1 R2 report:

```text
artifacts/perf2/perf2-1-generation-profile-r2.json
```

Required source evidence:

```text
12 samples
4 execution configurations
3 repetitions each
9 / 9 serial↔STREAM1 canonical pairs
PERF2.1 full report validation PASS
```

PERF2.2 does not advance ecology itself and does not call Workbench.

## Structural working-set evidence

PERF2.1 already captures:

```text
max_parent_chunk
max_candidate_chunk
parent_count
candidate_count
```

PERF2.2 derives the conservative record-pressure proxy:

```text
record_proxy_upper_bound
=
max_parent_chunk
+
max_candidate_chunk
```

This is explicitly:

```text
RECORD_PROXY_UPPER_BOUND
NOT BYTES
NOT A CLAIM THAT BOTH MAXIMA OCCUR SIMULTANEOUSLY
```

It is useful because the same canonical simulation results are already proven 9/9,
while the execution structure differs.

Rows are required for:

```text
SERIAL_REFERENCE
STREAM1_CHUNK_1
STREAM1_CHUNK_7
STREAM1_CHUNK_64
```

Each row summarizes three repetitions:

```text
count
p50
p95
mean
min
max
```

for:

```text
max_parent_chunk_records
max_candidate_chunk_records
record_proxy_upper_bound
final_parent_count
final_candidate_count
```

STREAM1 hard bounds remain:

```text
chunk 1:
parent <= 1
candidate <= 2

chunk 7:
parent <= 7
candidate <= 14

chunk 64:
parent <= 64
candidate <= 128
```

## Memory telemetry

Frozen PERF2.0 samples provide:

```text
engine_static_bytes
engine_static_peak_bytes
process_rss_bytes          optional
process_peak_rss_bytes     optional
```

PERF2.2 uses them honestly.

### engine_static_bytes

Classification:

```text
PROCESS_LOCAL_GODOT_STATIC_MEMORY_AT_SAMPLE_END
DIAGNOSTIC_ONLY
```

It is a real allocator observation, but sequential samples may be affected by allocator
retention and process history.

Therefore a serial/STREAM1 ratio may be reported, but:

```text
memory_reduction_claim = false
```

### engine_static_peak_bytes

Important semantic boundary:

```text
OS.get_static_memory_peak_usage()
=
PROCESS-LIFETIME HIGH-WATER MARK
```

Because PERF2.1 configurations execute sequentially in one Godot process, this metric is
not a clean per-configuration peak.

Therefore:

```text
engine_static_peak_cross_config_comparable = false
```

The high-water value is preserved and summarized only as diagnostic evidence.

PERF2.2 must not claim that a lower/higher row proves configuration-specific peak-memory
reduction.

### process RSS

PERF2.0 defines RSS fields as optional external measurements.

PERF2.2 records availability counts:

```text
process_rss_available_samples
process_peak_rss_available_samples
```

If unavailable, the report records zero available samples and `null` summaries.

PERF2.2 does not fabricate RSS.

## Comparisons

One comparison is produced for each STREAM1 chunk size.

Required:

```text
exact_pairs = 3
working_set_bound_claim = true
memory_reduction_claim = false
optimization_claim = false
```

Reported diagnostic factors:

```text
parent_record_reduction_factor_serial_over_stream
candidate_record_reduction_factor_serial_over_stream
record_proxy_reduction_factor_serial_over_stream
engine_static_end_ratio_serial_over_stream
```

Interpretation:

```text
record factor > 1
=
smaller structural bounded record pressure in STREAM1

engine_static_end ratio
=
diagnostic process-local allocator observation only
```

## Artifact

PERF2.2 produces:

```text
artifacts/perf2/perf2-2-working-set-memory-r1.json
```

Schema:

```text
distributed_world_simulator.ecology.evo7_perf2_2.working_set_memory_report.v1
```

Revision:

```text
ECO.EVO7-PERF2.2-R1
```

Required content:

```text
4 working_set_rows
4 memory_rows
3 comparisons
source PERF2.1 report binding
frozen PERF2.0 contract binding
report_hash
```

The artifact must survive JSON write → parse → full validation with identical recomputed
report hash.

Evidence tampering must fail closed.

## Authority boundary

PERF2.2 remains:

```text
canonical                 false
world_write               false
ecology_truth_write       false
generation_commit         false
biology_write             false
persistence_truth_write   false
network_write             false
measurement_only          true
side_channel_only         true
```

PERF2.2 is not world truth and cannot affect canonical ecology hashes.

## Protected predecessor guard

Relative to accepted control tip
`7044c13e8cd9b036f318192ba0d62c6f3393fb60`, PERF2.2 must not modify:

```text
scripts/ecology/shadow/**
eco_evo7_stream1_generation_stream_executor_v1.gd
eco_evo7_stream1_route_kernel_v1.gd
eco_evo7_perf2_measurement_contract_v1.gd
eco_evo7_perf2_measurement_probe_v1.gd
eco_evo7_perf21_generation_profiler_v1.gd
```

PERF2.2 is a derived measurement layer over accepted evidence.

## Runners

Ubuntu / primary local path:

```bash
GODOT_BIN=/path/to/exact-double-godot ./RUN_ECO_EVO7_PERF2_2_TESTS.sh
```

Windows / optional equivalent:

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.2 -GodotPath <exact-double>
```

The Linux runner performs:

```text
fresh import
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
artifact validation
final identity
tracked-clean guard
```

## Verification policy

Policy:

```text
ECO-RUNTIME-VERIFY-2026-08-31-R1
```

For this OS-neutral GDScript path:

```text
one fresh exact Ubuntu PASS
OR
one fresh exact Windows PASS
=
runtime acceptance satisfied
```

Second-OS execution is optional/non-blocking.

## Acceptance gate

PERF2.2 may be accepted only when one immutable HEAD has:

```text
exact Godot identity                    PASS
accepted PERF2.1 predecessor ancestry   PASS
frozen PERF2.0 blob                     PASS
protected predecessor diff              PASS

PERF1                                   PASS
STREAM1                                 PASS / 108 exact
PERF2.0                                 PASS
PERF2.1                                 PASS / 9 of 9
PERF2.2                                 PASS

working_set_rows                        4
memory_rows                             4
comparisons                             3

JSON round-trip                         PASS
report hash round-trip                  PASS
tamper rejection                        PASS

memory_reduction_claim                  false
optimization_claim                      false

final HEAD/TREE unchanged               PASS
tracked worktree clean                  YES

Project Control                         PASS
```

## PERF2.3 authorization rule

PERF2.3 Simulation Scaling stays blocked until PERF2.2 is accepted.

PERF2.2 acceptance authorizes scaling measurements, not optimization.

The expected transition is:

```text
PERF2.1 ACCEPTED
      ↓
PERF2.2 WORKING-SET / MEMORY
      ↓
PERF2.3 SIMULATION SCALING
      ↓
PERF2.4 RUNTIME OPTIMIZATION
```
