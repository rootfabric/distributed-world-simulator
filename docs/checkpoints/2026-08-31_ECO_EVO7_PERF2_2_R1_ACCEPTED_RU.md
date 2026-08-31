# ECO.EVO7 PERF2.2 R1 — ACCEPTED

Дата: 2026-08-31

Статус:

```text
PERF2.2 R1
ACCEPTED
EXACT LOCAL UBUNTU PASS
ECO-RUNTIME-VERIFY-2026-08-31-R1 SATISFIED
```

## Exact tested runtime subject

```text
branch
feature/eco-evo7-perf2-2-working-set-memory-r1

HEAD
c6bef3d6c20d7b468f88f9aaabade2fe809b63e6

TREE
57d4807095e1e1096a13b665b1ef1a1a90d5dc98
```

Implementation merge:

```text
0331b24fd80e31c3ecd19f990af5e669f2154ab3
```

The merge commit is not the tested executable identity. Runtime evidence belongs to
`c6bef3d6c20d7b468f88f9aaabade2fe809b63e6`.

## Predecessor

```text
accepted PERF2.1 control tip
7044c13e8cd9b036f318192ba0d62c6f3393fb60

accepted PERF2.1 tested HEAD
fccf4f99fd3c257abf90c37e584b965e2cddfa6a

frozen PERF2.0 contract blob
b076784f6b4016a0191e937c4e6ada1fe90c783b
```

## Ubuntu runtime acceptance evidence

```text
Godot
4.7.1.stable.double.custom_build.a13da4feb

host fingerprint
ee428a6139f8b5260a6626f4f7f375193144f9b5a9f280c59431470087c47d12

fresh detached worktree
PASS

final HEAD/TREE unchanged
PASS

tracked worktree clean
YES
```

Transitive gates:

```text
PERF1
PASS — 69 assertions

STREAM1
PASS — 195 assertions

STREAM1 exact comparisons
108 / 108

PERF2.0
PASS — 62 assertions

PERF2.1
PASS — 861 assertions
12 samples
9 / 9 exact cross-configuration pairs

PERF2.2
PASS — 170 assertions
```

Final marker:

```text
ECO.EVO7 PERF2.2 transitive working-set/memory R1 acceptance: PASS
```

## PERF2.2 report

```text
schema
distributed_world_simulator.ecology.evo7_perf2_2.working_set_memory_report.v1

report hash
e03e4418eb2a91e5795b07565dbdb0f26b4cc6e494021a8d268d9c18df906a2b

working_set_rows
4

memory_rows
4

comparisons
3

JSON round-trip
PASS

tamper rejection
PASS
```

## Structural working-set result

The deterministic structural proxy is:

```text
record_proxy_upper_bound
=
max_parent_chunk + max_candidate_chunk
```

This is a record-pressure upper-bound proxy, not bytes and not a claim that both maxima
occur simultaneously.

Observed exact rows:

| configuration | parent upper bound | candidate upper bound | record proxy upper bound | serial / stream reduction |
| --- | ---: | ---: | ---: | ---: |
| SERIAL_REFERENCE | 108 | 216 | 324 | 1.000000x |
| STREAM1_CHUNK_1 | 1 | 2 | 3 | 108.000000x |
| STREAM1_CHUNK_7 | 7 | 14 | 21 | 15.428571x |
| STREAM1_CHUNK_64 | 64 | 128 | 192 | 1.687500x |

All three STREAM1 configurations preserve the accepted canonical result:

```text
9 / 9 exact serial↔STREAM1 pairs
```

and all structural bounds are proven.

Accepted structural finding:

```text
STREAM1 provides a real deterministic bounded-record working-set reduction.

chunk 1
108.0x record-proxy reduction

chunk 7
15.43x record-proxy reduction

chunk 64
1.69x record-proxy reduction
```

This is a structural working-set claim, not a byte-memory claim.

## Allocator memory result

Observed terminal engine static memory:

```text
SERIAL
~57.85 MB

STREAM1
~57.91–57.94 MB
```

Observed serial/stream ratios:

```text
chunk 1
0.99894

chunk 7
0.99871

chunk 64
0.99848
```

This is effectively flat process-local allocator evidence with STREAM1 slightly higher
at sample end on this run. It does not prove a memory reduction.

Observed process-lifetime engine peak:

```text
72,212,481 bytes
identical in all four rows
```

This directly confirms the declared semantic boundary:

```text
engine_static_peak_bytes
=
PROCESS-LIFETIME HIGH-WATER MARK
NOT CLEAN CROSS-CONFIG PEAK MEMORY
```

Optional process RSS:

```text
available samples
0

classification
OPTIONAL / NOT FABRICATED
```

Therefore:

```text
working_set_bound_claim = true
memory_reduction_claim  = false
optimization_claim      = false
```

## PERF2.1 timing observed in this acceptance run

The fresh source PERF2.1 run on the same host reported:

```text
serial / stream wall ratio

chunk 1
0.945591

chunk 7
0.934530

chunk 64
0.938097
```

Important interpretation:

```text
ratio = serial / stream

ratio > 1
STREAM1 is faster

ratio < 1
SERIAL is faster
```

Therefore these values do NOT indicate a STREAM1 speedup. They indicate STREAM1 wall-time
overhead on this run of approximately:

```text
chunk 1
+5.75%

chunk 7
+7.01%

chunk 64
+6.60%
```

The magnitude varies between runs/hosts, which is why the PERF2 contract fences host
identity. The sign in accepted PERF2.1/PERF2.2 evidence remains the same: current bounded
STREAM1 trades extra execution overhead for dramatically lower deterministic structural
working-set pressure.

No optimization claim is authorized here.

## Project Control classification

Project Control runs on the PERF2.2 candidate completed subject-local preflight work:

```text
exact checkout
PASS

control candidate syntax/generation
PASS

checkpoint-session regression
PASS
```

The shared architecture/ownership compatibility regression was RED because of concurrent
project-wide dependency drift outside the PERF2.2 delta, including Matter files and
`config/control/project-program-registry.v1.json`.

Classification:

```text
GLOBAL PROJECT CONTROL
RED — EXTERNAL CONCURRENT DRIFT

PERF2.2 SUBJECT-LOCAL CONTROL PREFLIGHT
PASS

PERF2.2 RUNTIME ACCEPTANCE
PASS
```

This acceptance does not relabel the global Project Control RED as green and does not
repair or waive unrelated Matter/main ownership drift. PERF2.2 acceptance is bounded to
the ECO research lane and exact local runtime evidence.

## Acceptance decision

```text
PERF2.2 R1                       ACCEPTED
runtime acceptance               SATISFIED
structural working-set claim     ACCEPTED
byte-memory reduction claim      NOT MADE
optimization claim               NOT MADE
Windows verification             NOT REQUIRED
PERF2.3 Simulation Scaling       AUTHORIZED
```

Next checkpoint:

```text
ECO.EVO7/PERF2.3
Simulation Scaling
```
