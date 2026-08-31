# ECO.EVO7 PERF2.3 R1 — ACCEPTED

Дата: 2026-08-31

Статус:

```text
PERF2.3 R1
ACCEPTED
EXACT LOCAL UBUNTU PASS
ECO-RUNTIME-VERIFY-2026-08-31-R1 SATISFIED
```

## Exact tested runtime subject

```text
branch
feature/eco-evo7-perf2-3-simulation-scaling-r1

HEAD
34715ac5524d594003236ca6228c0b0ba5bb9e90

TREE
f97deaa1c3e8d31e1e5fc71394b7528426b1f585
```

Implementation merge:

```text
49df8196a59c57c35ba34dd8e0331cb420c894a0
```

The merge commit is not the tested executable identity.

## Environment

```text
Godot
4.7.1.stable.double.custom_build.a13da4feb

host fingerprint
f991491a82661a9fb4acdde311eb58ec9c5e105e9980475986c91b0de91e1042
```

## Transitive acceptance

```text
PERF1
PASS — 69

STREAM1
PASS — 195
exact 108/108

PERF2.0
PASS — 62

PERF2.1
PASS — 861
exact 9/9

PERF2.2
PASS — 170

PERF2.3
PASS — 1079
```

Final marker:

```text
ECO.EVO7 PERF2.3 transitive simulation-scaling R1 acceptance: PASS
```

## Scaling cardinality

```text
samples              36
scaling points       12
comparisons           9
trends                4
crossovers            3
generation advances 864
exact pairs          27 / 27
```

Audit alignment held for all 27 STREAM1 measured samples:

```text
stream_calls               12
serial_audit_calls          1
oracle_elided_generations  11
```

## Scale results

Wall ratio is defined as:

```text
serial / stream

> 1  STREAM1 faster
< 1  SERIAL_REFERENCE faster
```

Observed:

| scale | chunk | parents | candidates | wall ratio | generation ratio | record-proxy reduction | faster |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| AGE_2 | 1 | 108 | 216 | 0.909286 | 0.905532 | 108.000000x | SERIAL_REFERENCE |
| AGE_2 | 7 | 108 | 216 | 0.898832 | 0.895291 | 15.428571x | SERIAL_REFERENCE |
| AGE_2 | 64 | 108 | 216 | 0.948030 | 0.943472 | 1.687500x | SERIAL_REFERENCE |
| AGE_12 | 1 | 373 | 746 | 0.869919 | 0.867676 | 373.000000x | SERIAL_REFERENCE |
| AGE_12 | 7 | 373 | 746 | 0.802302 | 0.797886 | 53.285714x | SERIAL_REFERENCE |
| AGE_12 | 64 | 373 | 746 | 0.842280 | 0.838184 | 5.828125x | SERIAL_REFERENCE |
| AGE_22 | 1 | 937 | 1874 | 0.902205 | 0.895048 | 937.000000x | SERIAL_REFERENCE |
| AGE_22 | 7 | 937 | 1874 | 0.854621 | 0.847653 | 133.857143x | SERIAL_REFERENCE |
| AGE_22 | 64 | 937 | 1874 | 0.898818 | 0.894178 | 14.640625x | SERIAL_REFERENCE |

No crossover was observed.

## Scaling trends AGE_2 → AGE_22

```text
population growth
7.905512x
```

SERIAL_REFERENCE:

```text
wall growth              8.780944x
generation growth        8.717314x
record-proxy growth      8.675926x
```

STREAM1_CHUNK_1:

```text
wall growth              8.849860x
generation growth        8.819421x
record-proxy growth      1.000000x
```

STREAM1_CHUNK_7:

```text
wall growth              9.235199x
generation growth        9.207232x
record-proxy growth      1.000000x
```

STREAM1_CHUNK_64:

```text
wall growth              9.261711x
generation growth        9.197885x
record-proxy growth      1.000000x
```

Accepted scaling finding:

```text
STREAM1 keeps structural record-pressure bounded as the simulation grows,
while serial structural pressure scales with the population.

Current STREAM1 execution still carries runtime overhead on every tested point.
No crossover was observed.
```

Approximate STREAM1 wall overhead relative to serial on this host:

```text
AGE_2
chunk 1  +9.98%
chunk 7  +11.26%
chunk 64 +5.48%

AGE_12
chunk 1  +14.95%
chunk 7  +24.64%
chunk 64 +18.73%

AGE_22
chunk 1  +10.84%
chunk 7  +17.01%
chunk 64 +11.26%
```

These values are host-local evidence, not production thresholds.

## Artifact integrity

```text
report
artifacts/perf2/perf2-3-simulation-scaling-r1.json

report hash
385415ed6db1328c7fbc3fefe737d431c801ac0feb5db539b343825cc4906a97

JSON validation
PASS

JSON round-trip
PASS

recomputed report hash
PASS

tamper rejection
PASS
```

## Claims

```text
simulation_scaling_observation  true
crossover_classification        HOST_LOCAL_DIAGNOSTIC_ONLY
memory_reduction_claim          false
optimization_claim              false
```

## Final integrity

```text
HEAD unchanged
PASS

TREE unchanged
PASS

tracked worktree clean
YES
```

## Project Control classification

Candidate Project Control subject-local preflight remained green:

```text
exact checkout                         PASS
control candidate syntax/generation    PASS
checkpoint-session regression          PASS
```

Global architecture/ownership compatibility remains RED due concurrent project-wide
Matter/project-program-registry drift outside the PERF2.3 delta.

This acceptance does not relabel that global RED as green and does not repair unrelated
ownership drift.

## Acceptance decision

```text
PERF2.3 R1                 ACCEPTED
runtime acceptance          SATISFIED
Windows verification        NOT REQUIRED
crossover                   NOT OBSERVED
optimization claim          NOT MADE
PERF2.4 Runtime Optimization AUTHORIZED
```

Next checkpoint:

```text
ECO.EVO7/PERF2.4
Runtime Optimization
```
