# ECO.EVO7 VIS4.9 — Performance / LOD R1 Candidate

Дата: 2026-08-31

Статус:

~~~text
VIS4.9 R1
UBUNTU EXACT-SOURCE DOUBLE-GODOT VERIFIED
CLOSED
~~~

## Frozen executable subject

~~~text
HEAD:
ab44617d8961add81a6c9f245c99d0b68eaeab52

TREE:
9d543a3db4f54a676e9f25152785c36a72c56a30
~~~

Predecessor: VIS4.8 CLOSED.

## Реализовано

VIS4.9 добавляет VIS4-local observability поверх уже accepted VIS4.3/PH5/PLAY0 path. Второго renderer/profiler не создаётся.

PH5 bridge теперь измеряет diagnostic wall-clock для:

~~~text
GrowthGraph reconstruction
RenderDescription build
Representation build
PH5 Materializer
~~~

PLAY0 PH5 renderer публикует:

~~~text
snapshot apply count / total / avg / max ms
materialization build count / total / avg / max ms
cache entries / hits / misses / hit rate
LOD update count / switch count / total / avg / max ms

tier counts
visible individuals
branch primitive count
foliage instance count
far primitive count
cost_units
draw_call_proxy
~~~

Wall-clock timings явно diagnostic-only и не входят в source/geometry identity.

draw_call_proxy — только workload proxy: branch mesh, foliage MultiMesh и far mesh дают по одному потенциальному вызову. Это не RenderingServer draw-call truth.

## Cache / LOD contract

Cache miss обязан соответствовать реальному build:

~~~text
materialization_cache_miss_count
==
materialization_build_count
~~~

Cache hit возвращает exact previous materialization без bridge rebuild.

Focused live campaign проводит реальный PH5 record через:

~~~text
T0 -> T2 -> T0(cache reuse) -> T4 -> T0
~~~

и проверяет:

~~~text
T0:
  branches > 0
  foliage > 0
  cost = 10000

T2:
  branches = 0
  foliage = 0
  far canopy primitive = 1
  cost = 250

T4:
  no individual node
  zero drawable workload
  draw_call_proxy = 0
  cost = 1
~~~

Repeated stable T0 view не должен вызывать LOD switch, cache lookup или materialization build.

T0 return после другого tier обязан дать cache hit и восстановить exact previous materialization_hash.

## F8 observatory

Новый read-only F8 surface показывает:

~~~text
visible plant / tier counts
cache hit/miss/build evidence
GrowthGraph / RenderDescription / Representation / Materializer timings
branch / foliage / far workload
cost units
draw-call proxy
frame average/min/max ms
estimated FPS
~~~

F6, F7 и F8 используют один diagnostic HUD slot и визуально взаимоисключаются.

Frame time / FPS являются observational-only и не являются PERF2 acceptance threshold.

## Structural evidence

Новый model:

~~~text
scripts/labs/ecology/eco_evo7_vis4_9_performance_lod_evidence.gd
~~~

Его structural_evidence_hash исключает wall-clock timings и FPS и связывает только structural/source counters.

Contract:

~~~text
presentation_only = true
ecology_authority = false
network_authority = false
persistence_authority = false

timings_diagnostic_only = true
fps_observational_only = true
draw_calls_are_proxy = true

perf2_convergence_required = true
~~~

Следовательно VIS4.9 не заменяет PERF2.CONV и не является финальной PLAY1 performance acceptance.

## Non-causal invariants

LOD/performance campaign сохраняет:

~~~text
ecology_state_hash
VIS4.5 individuality identity
VIS4.6 grid appearance identity
~~~

Geometry/materialization identity может и должна меняться между tiers.

Новой biology, generation, reproduction/mutation/dispersal, persistence или network authority не добавлено.

## Acceptance

Focused test:

~~~text
tests/ecology/eco_evo7_vis4_9_performance_lod_acceptance.gd
~~~

Результат:

~~~text
ECO.EVO7 VIS4.9 Performance / LOD: PASS (116 assertions)
~~~

Observed diagnostic sample:

~~~text
final cache hit rate: 0.282
final aggregate cost units: 12280
observational frame ms: 7.530
~~~

Эти значения — evidence конкретного запуска, не portable thresholds.

Canonical runners:

~~~text
RUN_ECO_EVO7_VIS4_9_TESTS.sh
RUN_ECO_EVO7_VIS4_9_TESTS.ps1
~~~

Final marker:

~~~text
ECO.EVO7 VIS4.9 Performance / LOD candidate: PASS
~~~

## Exact Ubuntu verification

Для доставки frozen source использован временный validation-only export:

~~~text
workflow run:
33382564515
SUCCESS

temporary PR:
#398
CLOSED WITHOUT MERGE
~~~

До archive export GitHub независимо подтвердил exact HEAD/TREE. Локальный reconstructed tree совпал:

~~~text
9d543a3db4f54a676e9f25152785c36a72c56a30
~~~

Использован Godot из project-attached canonical archive:

~~~text
version:
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

Полный canonical nested runner завершился:

~~~text
RC=0
~~~

Транзитивная цепочка GREEN:

~~~text
FFF2                       PASS / 56
PH2                        PASS / 107
VIS4.0                     PASS / 176
LS3.4                      PASS / 45
LS3.6                      PASS / 114
VIS4.1                     PASS / 598
VIS1                       PASS / 41
VIS2                       PASS / 69
VIS3                       PASS / 107
VIS4.2                     PASS / 1265
PH5                        PASS / 720
PH5-S2                     PASS / 387
PH5-S3                     PASS / 49 + 61
PH5-S4                     PASS / 5026 + 430
VIS4.3                     PASS / 752
PLAY0                      PASS / 103
VIS4.4                     PASS / 74
VIS4.5                     PASS / 491
VIS4.6                     PASS / 796
VIS4.7                     PASS / 106
VIS4.8                     PASS / 106
VIS4.9                     PASS / 116
~~~

VIS4.8 осталось:

~~~text
RENDERER FIDELITY: PASS
LIVE DIVERSITY: LIVE_DIVERSITY_SUFFICIENT
~~~

Full log SHA-256:

~~~text
e1b20145a18ac4059af9b15dfc692e7df4118c2bdf8fa55b46a742b6c939d2e0
~~~

Post-run synthetic baseline:

~~~text
HEAD TREE:
9d543a3db4f54a676e9f25152785c36a72c56a30

tracked status:
clean

untracked Godot import artifacts:
128 *.gd.uid
~~~

## Qualification

~~~text
VIS4.9 IMPLEMENTED
EXACT UBUNTU DOUBLE-GODOT GREEN
FULL CANONICAL RUNNER GREEN
FOCUSED 116/116
TRACKED TREE CLEAN

VIS4.9 READY TO CLOSE
~~~


## Closure status

VIS4.9 is closed on the frozen executable subject:

~~~text
HEAD:
ab44617d8961add81a6c9f245c99d0b68eaeab52

TREE:
9d543a3db4f54a676e9f25152785c36a72c56a30
~~~

Accepted evidence:

~~~text
full canonical runner:
RC=0

VIS4.9 focused:
PASS / 116 assertions

final candidate marker:
PRESENT

tracked source tree:
clean
~~~

Durable closure:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_9_PERFORMANCE_LOD_UBUNTU_EXACT_SOURCE_VERIFIED_CLOSED_R1_RU.md
~~~

Final status:

~~~text
VIS4.9 CLOSED
VIS4 MORPHOLOGY LINE COMPLETE THROUGH VIS4.9
NEXT: PERF2.CONV / STREAM1 + VIS4 CONVERGENCE
~~~
