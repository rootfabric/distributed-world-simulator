# ECO.EVO7 PERF2.4 R1 — Runtime Optimization

Дата: 2026-08-31

Статус:

```text
IMPLEMENTATION CANDIDATE
ONE EXACT LOCAL PASS REQUIRED
UBUNTU OR WINDOWS
```

## Accepted predecessor

```text
PERF2.3 R1 ACCEPTED

exact tested HEAD
34715ac5524d594003236ca6228c0b0ba5bb9e90

exact tested TREE
f97deaa1c3e8d31e1e5fc71394b7528426b1f585

accepted control tip
4997f7116d0e4ac40ed88fe8a41a7b5029621d71
```

Frozen PERF2.0 measurement contract:

```text
ECO.EVO7-PERF2.0-R1

blob
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Baseline problem

Accepted PERF2.3 established:

```text
27 / 27 exact serial↔STREAM1 canonical pairs
STREAM1 bounded structural working set
no observed serial/STREAM1 crossover
SERIAL_REFERENCE faster at all 9 tested scale/chunk points
```

The structural benefit is large and grows with population, but current STREAM1
orchestration pays unnecessary execution overhead.

PERF2.4 is authorized to change runtime orchestration only if exact identity and bounded
working-set semantics remain unchanged.

## Root cause targeted by R1

STREAM1 R1 performed redundant canonicalization inside every chunk:

```text
for every chunk:
  parent re-sort
  candidate sort
  route sort
  recruitment hash-map reconstruction
  recruitment sort
  recruitment context rebuild

after all chunks:
  candidate full-generation sort
  route full-generation sort
  recruitment full-generation sort
```

The chunk-local sorts were redundant because the generation proposal is canonicalized
again before proposal hashes, audit parity and LS3.3 authority validation.

The recruitment context was immutable for the whole generation and therefore did not
need to be rebuilt for every chunk.

## Optimized pipeline

New default mode:

```text
OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION
```

Retained A/B baseline mode:

```text
LEGACY_PER_CHUNK_CANONICALIZATION
```

Optimized generation path:

```text
1. sort parents once for the generation
2. slice already-sorted parent chunks
3. build candidate chunk without re-sorting parents/candidates
4. build route chunk preserving candidate input order
5. evaluate recruitment by aligned candidate/route index
6. build immutable recruitment context once per generation
7. append bounded chunk results
8. canonicalize candidates/routes/recruitment once at generation boundary
9. compute unchanged pool/proposal hashes
10. execute unchanged monolithic audit oracle on audit generations
11. LS3.3 performs unchanged proposal authority validation + atomic publication
```

## Runtime files allowed to change

PERF2.4 R1 runtime allowlist:

```text
scripts/ecology/perf/eco_evo7_stream1_generation_stream_executor_v1.gd
scripts/ecology/perf/eco_evo7_par3_candidate_kernel_v1.gd
scripts/ecology/perf/eco_evo7_stream1_route_kernel_v1.gd
```

New measurement-only profiler:

```text
scripts/ecology/perf/eco_evo7_perf24_runtime_optimization_profiler_v1.gd
```

Forbidden to change in this checkpoint:

```text
scripts/ecology/shadow/**
PAR0 recruitment mathematical kernel
PERF2.0 contract/probe
PERF2.1 profiler
PERF2.2 profiler
PERF2.3 profiler
biology/mutation formulas
persistence/network authority
```

## Mathematical identity boundary

No formula changes are permitted.

Unchanged:

```text
candidate build formula
candidate_hash
dispersal seed
route formula
route_hash
recruitment evaluation formula
recruitment_event_hash
candidate_pool_hash semantics
route_pool_hash semantics
recruitment_pool_hash semantics
proposal_hash
audit generation schedule
LS3.3 proposal validation
LS3.3 atomic generation publication
```

The optimized chunk path differs only in temporary ordering work before the single
generation-boundary canonicalization.

## Legacy A/B seam

The old per-chunk canonicalization path remains explicitly selectable only for PERF2.4
A/B evidence:

```text
pipeline_mode =
LEGACY_PER_CHUNK_CANONICALIZATION
```

Production/default setup without an explicit mode uses:

```text
OPTIMIZED_GENERATION_BOUNDARY_CANONICALIZATION
```

Unknown pipeline modes fail closed.

## Deterministic operation evidence

STREAM1 executor exposes side-channel counters that never enter proposal identity:

```text
legacy_generation_calls
optimized_generation_calls

chunk_local_parent_sorts
chunk_local_candidate_sorts
chunk_local_route_sorts
chunk_local_recruitment_sorts

recruitment_context_builds
generation_boundary_sorts
```

For a 12-generation measured optimized sample:

```text
optimized_generation_calls = 12
legacy_generation_calls    = 0

chunk_local_parent_sorts      = 0
chunk_local_candidate_sorts   = 0
chunk_local_route_sorts       = 0
chunk_local_recruitment_sorts = 0

recruitment_context_builds = 12
generation_boundary_sorts  = 36
```

For the legacy A/B sample:

```text
legacy_generation_calls = 12

each chunk-local sort count
=
measured chunks processed

recruitment_context_builds
=
measured chunks processed

generation_boundary_sorts
=
36
```

Thus operation reduction is deterministic evidence independent of wall-clock noise.

## A/B campaign

Frozen scale axis from PERF2.3:

```text
AGE_2
AGE_12
AGE_22
```

Chunk sizes:

```text
1
7
64
```

Per scale/chunk:

```text
3 legacy repetitions
3 optimized repetitions
```

Total:

```text
3 scales
× 3 chunks
× 3 repetitions
× 2 pipeline modes
=
54 samples

27 exact legacy↔optimized pairs

1296 total generation advances
```

Execution order is balanced:

```text
repetition 0: legacy → optimized
repetition 1: optimized → legacy
repetition 2: legacy → optimized
```

This reduces systematic warm-cache ordering bias.

## Optimization thresholds

PERF2.4 is not accepted merely because fewer operations are executed.

The runtime optimization claim requires all of:

```text
exact legacy↔optimized parity            27 / 27

bounded structural working set           PRESERVED

deterministic operation reduction         PROVEN

wall geomean legacy / optimized          >= 1.02

STREAM1-total geomean legacy / optimized >= 1.03

wall points improved                      >= 6 / 9

wall points non-regressed                 9 / 9

minimum allowed point ratio               0.97
```

Ratio semantics:

```text
legacy / optimized > 1
optimized pipeline is faster
```

No individual point may regress by more than 3%.

## Serial crossover

PERF2.4 does NOT require optimized STREAM1 to become faster than serial.

The claim at this checkpoint is:

```text
optimized STREAM1 is materially faster than legacy STREAM1
while preserving exact canonical parity
and bounded structural working-set semantics
```

Serial crossover remains a useful observation, but:

```text
serial_crossover_required = false
```

## Artifact

Output:

```text
artifacts/perf2/perf2-4-runtime-optimization-r1.json
```

Schema:

```text
distributed_world_simulator.ecology.evo7_perf2_4.runtime_optimization_report.v1
```

Required:

```text
samples       54
comparisons    9
exact pairs   27 / 27
```

Report must survive:

```text
JSON write
→ parse
→ numeric normalization
→ A/B comparison recomputation from samples
→ report hash recomputation
→ full validation
```

Tampering with performance evidence must fail closed.

## Claims

Only after all frozen thresholds pass:

```text
canonical_parity                  true
bounded_working_set_preserved     true
deterministic_operation_reduction true
serial_crossover_claim            false
optimization_claim                true
```

## Ubuntu runner

```bash
GODOT_BIN=/path/to/exact-double-godot bash ./RUN_ECO_EVO7_PERF2_4_TESTS.sh
```

Transitive chain:

```text
fresh import
PERF1
STREAM1
PERF2.0
PERF2.1
PERF2.2
PERF2.3
PERF2.4

artifact validation
A/B thresholds
final HEAD/TREE
tracked-clean
```

Final marker:

```text
ECO.EVO7 PERF2.4 transitive runtime-optimization R1 acceptance: PASS
```

## Verification policy

Under:

```text
ECO-RUNTIME-VERIFY-2026-08-31-R1
```

one exact local Ubuntu OR Windows PASS is sufficient.

Second OS evidence is optional/non-blocking.

## Acceptance decision rule

PERF2.4 may close only if the exact candidate demonstrates:

```text
transitive regressions              PASS
STREAM1 serial parity               PASS
PERF2.3 27/27 serial parity         PASS
PERF2.4 27/27 legacy/optimized      PASS
bounded structural working set      PRESERVED
deterministic operation reduction   PROVEN
performance thresholds              PASS
optimization_claim                  TRUE
JSON/tamper                          PASS
final identity                      UNCHANGED
tracked worktree                    CLEAN
```

If timing thresholds fail, the checkpoint remains open and the runtime optimization must
be repaired on a new exact HEAD. Thresholds must not be weakened after observing the
result.

## Next

Successful PERF2.4 closes the PERF2.SIM lane.

The next route transition is PERF2.CONV, gated separately by the accepted VIS4 /
PLAY0.MORPH presentation lane.
