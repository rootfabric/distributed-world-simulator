# ECO.EVO7 — Parallel STREAM1 / VIS4 / PERF2 Roadmap Amendment R2

Дата: 2026-08-30  
Статус: ACTIVE PARALLEL EXECUTION POLICY / ROADMAP AMENDMENT  
Branch: feature/eco-evo7-vis4-evolved-plant-morphology-r1

## Identity at amendment time

~~~text
PAR3 R3.2 base
8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf

STREAM1 active head
4d0d95a2f0cf8aeb9642765c17a071f039e0f1c4

VIS4 roadmap head before amendment
a6cedcd018a03740961c4b9d2798cba678f5009f
~~~

## Decision

STREAM1 and VIS4 are already being developed in parallel.

Completion of STREAM1 does NOT require waiting for PLAY0.MORPH before continuing performance work.

The old coarse dependency:

~~~text
STREAM1 + VIS4
   -> PERF2
   -> PLAY1
~~~

is refined into:

~~~text
                         PAR3 R3.2
                             |
                +------------+------------+
                |                         |
                v                         v
             STREAM1                    VIS4
                |                         |
                v                         v
           PERF2.SIM                PLAY0.MORPH
                |                         |
                +------------+------------+
                             |
                             v
                        PERF2.CONV
                             |
                             v
                    PLAY1 LIVING REGION
~~~

## PERF2.SIM

Can start immediately after STREAM1 independent acceptance.

Scope:

~~~text
PERF2.0 Measurement Contract
PERF2.1 STREAM1 Generation Profiling
PERF2.2 Working-set / Memory
PERF2.3 Simulation Scaling
PERF2.4 Runtime Optimization
~~~

This path is not blocked by VIS4.

It may profile:

- bounded generation throughput;
- CPU phase timing;
- working-set and memory pressure;
- allocator behavior;
- proposal/commit cost;
- scaling with cell/population count;
- simulation-side parallelism;
- non-rendering bottlenecks.

## VIS4 / PLAY0.MORPH

Continues independently.

VIS4 may perform its own local materialization/LOD measurements, but those results do not constitute final PLAY1 performance acceptance.

## PERF2.CONV

Requires both:

~~~text
STREAM1 ACCEPTED
+
VIS4 / PLAY0.MORPH ACCEPTED
~~~

Scope:

~~~text
PERF2.5 VIS4 Materialization Profiling
PERF2.6 PH5 LOD / Cache Tuning
PERF2.7 STREAM1 + VIS4 Integrated Load
PERF2.8 PLAY1 Performance Acceptance
~~~

Only this integrated gate proves that the living-region composition is performant under:

~~~text
bounded ecology generation
+
live planet
+
real PH5 morphology
+
LOD/materialization/cache workload
~~~

## Canonical execution rule

~~~text
if STREAM1 finishes first:
    start PERF2.SIM immediately
    continue VIS4 in parallel

if VIS4 finishes first:
    continue VIS4-local profiling/acceptance
    do not fabricate PERF2.SIM evidence without accepted STREAM1

when both are accepted:
    run PERF2.CONV

only PERF2.CONV GREEN:
    opens PLAY1 LIVING REGION acceptance
~~~

## Why this amendment exists

Without this split, STREAM1 could sit idle waiting for an unrelated presentation track.

Conversely, accepting all of PERF2 before VIS4 would under-measure the actual PLAY1 workload because current PLAY0 plants are only BoxMesh/SphereMesh while PLAY0.MORPH adds GrowthGraph, branch mesh, foliage MultiMesh, LOD and materialization/cache work.

The split preserves parallel development while keeping final performance evidence honest.

## Documentation source

Updated live roadmap:

~~~text
docs/plans/ECO_EVO7_VIS4_EVOLVED_PLANT_MORPHOLOGY_IMPLEMENTATION_PLAN_RU.md
~~~

This R2 amendment supersedes only the previous coarse PERF2 dependency ordering. It does not change VIS4 biology boundaries, STREAM1 authority, or previous acceptance evidence.

## Current program state

~~~text
PARALLEL WORK ACTIVE

STREAM1 -> active
VIS4    -> active roadmap/work line

next after STREAM1 acceptance:
PERF2.SIM

final join:
PERF2.CONV
~~~
