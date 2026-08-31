# ECO.EVO7 PERF2.3 R1 — Simulation Scaling

Дата: 2026-08-31

Статус:

```text
IMPLEMENTATION CANDIDATE
ONE EXACT LOCAL PASS REQUIRED
UBUNTU OR WINDOWS
```

Predecessor:

```text
PERF2.2 R1 ACCEPTED

exact tested HEAD
c6bef3d6c20d7b468f88f9aaabade2fe809b63e6

exact tested TREE
57d4807095e1e1096a13b665b1ef1a1a90d5dc98

accepted control tip
922b8b377faf19e36e58cf111c5dc917e83e09e1
```

Frozen PERF2.0 contract blob:

```text
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Goal

PERF2.3 measures how accepted serial and bounded STREAM1 execution scale as the same
deterministic ecology workload ages into later generations.

PERF2.3 does not modify runtime and does not synthesize a larger initial population.

The scale axis is:

```text
GENERATION_AGE_PRECONDITION
```

This avoids changing the accepted Workbench runtime, whose public contract owns the
initial-record count.

## Scaling points

Frozen precondition points:

```text
AGE_2
precondition generations = 2
measured window = 3..14

AGE_12
precondition generations = 12
measured window = 13..24

AGE_22
precondition generations = 22
measured window = 23..34
```

Every point then executes:

```text
12 measured generations
3 repetitions
```

Execution configurations:

```text
SERIAL_REFERENCE
STREAM1_CHUNK_1
STREAM1_CHUNK_7
STREAM1_CHUNK_64
```

Total:

```text
3 scale points
× 4 execution configurations
× 3 repetitions
=
36 samples

total generation advances
=
864
```

## Audit alignment

STREAM1 interval:

```text
10 generations
```

Scale points differ by exactly 10 precondition generations.

Therefore every measured window contains exactly one equivalent interval audit:

```text
AGE_2   → audit generation 10
AGE_12  → audit generation 20
AGE_22  → audit generation 30
```

Required measured-window telemetry for every STREAM1 sample:

```text
stream_calls = 12
serial_audit_calls = 1
oracle_elided_generations = 11
```

This prevents the scaling result from being confounded by different audit counts.

## Canonical parity

For every scale point:

```text
3 repetitions
× 3 STREAM1 chunk sizes
=
9 exact serial↔STREAM1 pairs
```

Across all scale points:

```text
27 / 27 exact canonical pairs required
```

Exact parity uses the frozen PERF2.0 execution-comparison contract.

Timing, memory and target SHA do not enter canonical ecology identity.

## Scaling points

The report produces 12 point rows:

```text
3 scale points × 4 execution configurations
```

Each row summarizes:

```text
wall_ms
generation_total_ms
final_population
final_parent_count
final_candidate_count
record_proxy_upper_bound
engine_static_end_bytes
```

Each summary contains:

```text
count
p50
p95
mean
min
max
```

Structural record proxy remains:

```text
max_parent_chunk + max_candidate_chunk
```

It remains a record-pressure upper bound, not bytes.

## Serial ↔ STREAM1 comparisons

The report produces:

```text
3 scale points × 3 chunk sizes
=
9 comparisons
```

Each comparison records:

```text
exact_pairs = 3

serial_wall_p50_ms
stream_wall_p50_ms
observed_wall_ratio_serial_over_stream

serial_generation_p50_ms
stream_generation_p50_ms
observed_generation_ratio_serial_over_stream

serial_parent_p50
stream_parent_p50

serial_candidate_p50
stream_candidate_p50

serial_record_proxy_p50
stream_record_proxy_p50
record_proxy_reduction_factor_serial_over_stream
```

Ratio semantics:

```text
serial / stream > 1
STREAM1 observed faster

serial / stream < 1
SERIAL_REFERENCE observed faster
```

This is host-local measurement evidence only.

## Scaling trends

Four trend rows are produced:

```text
SERIAL_REFERENCE
STREAM1_CHUNK_1
STREAM1_CHUNK_7
STREAM1_CHUNK_64
```

Each compares AGE_2 with AGE_22:

```text
population_growth_factor
wall_growth_factor
generation_time_growth_factor
record_proxy_growth_factor
```

These are:

```text
HOST_LOCAL_DIAGNOSTIC
```

They are not optimization acceptance.

## Crossover analysis

One crossover analysis is produced for each STREAM1 chunk size.

For each chunk, PERF2.3 records the three wall ratios and classifies the observed
faster side at each scale point:

```text
SERIAL_REFERENCE
STREAM1
EQUAL
```

If the faster side changes between adjacent scale points, PERF2.3 records:

```text
crossover_observed = true
first_observed_transition = AGE_X_TO_AGE_Y
```

This classification is explicitly:

```text
HOST_LOCAL_DIAGNOSTIC_ONLY
```

It is not a production tuning threshold and is not an optimization claim.

## Claims

Allowed:

```text
simulation_scaling_observation = true
crossover_observation = HOST_LOCAL_DIAGNOSTIC_ONLY
```

Forbidden:

```text
memory_reduction_claim = false
optimization_claim = false
```

PERF2.4 is the first checkpoint allowed to propose runtime optimization, and only after
PERF2.3 acceptance.

## Artifact

Output:

```text
artifacts/perf2/perf2-3-simulation-scaling-r1.json
```

Schema:

```text
distributed_world_simulator.ecology.evo7_perf2_3.simulation_scaling_report.v1
```

Revision:

```text
ECO.EVO7-PERF2.3-R1
```

Required report cardinality:

```text
samples         36
scaling_points  12
comparisons      9
trends           4
crossovers       3
exact pairs     27 / 27
```

The report must survive:

```text
JSON write
→ parse
→ recomputed report hash
→ full validation
```

Evidence tampering must fail closed.

## Authority boundary

PERF2.3 remains:

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

## Protected predecessor

Relative to accepted PERF2.2 control tip
`922b8b377faf19e36e58cf111c5dc917e83e09e1`, PERF2.3 must not modify:

```text
scripts/ecology/shadow/**
eco_evo7_stream1_generation_stream_executor_v1.gd
eco_evo7_stream1_route_kernel_v1.gd
eco_evo7_perf2_measurement_contract_v1.gd
eco_evo7_perf2_measurement_probe_v1.gd
eco_evo7_perf21_generation_profiler_v1.gd
eco_evo7_perf22_working_set_memory_profiler_v1.gd
```

## Ubuntu runner

Primary local execution:

```bash
GODOT_BIN=/path/to/exact-double-godot bash ./RUN_ECO_EVO7_PERF2_3_TESTS.sh
```

The runner performs:

```text
fresh import

PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3

artifact structural validation
27/27 parity check
scaling profile printout
trend printout
crossover printout

final HEAD/TREE unchanged
tracked-clean guard
```

## Acceptance

Under:

```text
ECO-RUNTIME-VERIFY-2026-08-31-R1
```

one exact local Ubuntu OR Windows PASS is sufficient.

Required exact gate:

```text
exact Godot identity                     PASS
accepted PERF2.2 ancestry                PASS
frozen PERF2.0 blob                      PASS
protected predecessor diff               PASS

PERF1                                    PASS
STREAM1                                  PASS / 108 exact
PERF2.0                                  PASS
PERF2.1                                  PASS / 9 of 9
PERF2.2                                  PASS
PERF2.3                                  PASS

samples                                  36
scaling points                           12
comparisons                               9
trends                                    4
crossovers                                3
exact pairs                              27 / 27

JSON round-trip                          PASS
report-hash round-trip                   PASS
tamper rejection                         PASS

optimization_claim                       false
memory_reduction_claim                   false

final HEAD/TREE unchanged                PASS
tracked worktree clean                   YES
```

## Next

PERF2.4 remains blocked until PERF2.3 acceptance.

Expected route:

```text
PERF2.2 ACCEPTED
      ↓
PERF2.3 SIMULATION SCALING
      ↓
PERF2.4 RUNTIME OPTIMIZATION
```
