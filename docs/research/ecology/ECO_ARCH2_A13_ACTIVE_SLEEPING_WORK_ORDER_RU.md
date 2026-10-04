# ECO ARCH2 A13 — Active / Sleeping Population Scheduling / Work Order R1

Статус: implementation candidate.

База:
7ffff8aad3591a67972f89eeb506e9ec4ad0dc04
(A13 Spatial Workset Addressing merged main)

## Цель

Добавить первый безопасный слой ACTIVE / SLEEPING scheduling поверх стабильных
spatial addresses без reduced biology, отдельной per-tile truth или изменения
canonical ecology.

R1 вводит только scheduler cadence:

canonical spatial tile
→ explicit activity classification
→ ACTIVE / SLEEPING
→ deterministic scheduler debt
→ exact catch-up
→ same canonical ecology truth

Activity/cadence metadata является scheduler-only projection и не хранится в
organism state, EcologyRuntime state или checkpoint.

## Ключевое ограничение R1

A5 сохраняет один глобальный ресурсный барьер:

prepare all demands
→ ONE GLOBAL Field.allocate_demands()
→ advance all granted organisms

Поэтому при общем canonical field нельзя корректно продвинуть ACTIVE tile на
несколько canonical ticks, исключив SLEEPING tile, а потом догнать только sleeping:
пропущенные sleeping demands могли изменить grants активных организмов.

R1 закрывает эту ловушку fail-closed.

Если существует sleeping debt, ACTIVE tiles не получают отдельный canonical commit.
До cadence boundary runtime остаётся byte-identical исходному state. На wake runtime
последовательно replay-ит КАЖДЫЙ пропущенный canonical tick через обычный
spatial scheduler, заново вычисляя spatial worksets на каждом tick и сохраняя один
глобальный allocation barrier.

Это reference/exact semantics. R1 ещё не является performance optimization для
mixed ACTIVE/SLEEPING world.

## R1 contract

- schema: `dws.ecology.activity-cadence-plan.v1`;
- default sleeping cadence = 4 scheduler ticks;
- max sleeping cadence = 64;
- max exact catch-up debt = 64 ticks;
- activity classifier input R1 = explicit set of active spatial addresses;
- unspecified existing addresses are SLEEPING;
- active-address input order is canonicalized;
- unknown active address rejected;
- plan is bound to exact spatial geometry/population projection;
- plan contains scheduler frontier:
  - `committed_scheduler_tick`;
  - `target_scheduler_tick`;
  - `debt_ticks`;
- ACTIVE cadence = 1;
- SLEEPING cadence = configured deterministic cadence;
- scheduler frontier must be anchored to canonical `Runtime.tick`;
- pre-wake defer mutates zero canonical bytes;
- wake replays all debt sequentially through `step_spatial_scheduled()`;
- catch-up failure is atomic: caller receives no partial canonical state;
- scheduler metadata is absent from Runtime/checkpoint persistence.

## Execution invariant

For mixed ACTIVE/SLEEPING R1:

1. derive current spatial addresses from canonical positions;
2. classify addresses ACTIVE/SLEEPING;
3. before sleeping cadence is due:
   - report scheduler debt;
   - do not advance canonical ecology;
4. at wake:
   - replay every missing tick in order;
   - on every replay tick recompute spatial worksets;
   - prepare all population demands;
   - execute ONE GLOBAL allocation;
   - advance all population;
   - perform propagule admission / mutation / feedback normally;
5. canonical `Runtime.tick` catches up exactly to target scheduler tick.

No synthetic tick jump is permitted.

## Acceptance

- four spatial tiles classify deterministically as ACTIVE/SLEEPING;
- population permutation cannot change activity plan bytes;
- unknown/tampered/stale activity plans fail closed;
- sleeping debt below cadence returns success+deferred with zero state mutation;
- all-ACTIVE cadence commits one exact canonical tick immediately;
- all-SLEEPING cadence wakes deterministically;
- mixed ACTIVE/SLEEPING wake replays all missing ticks;
- 8-tick wake with reproduction+mutation is byte/hash-identical to 8 continuous
  spatial ticks;
- checkpoint serialization is identical continuous vs catch-up;
- activity schema never appears in Runtime/checkpoint bytes;
- invalid mutation options during multi-tick catch-up return no partial state;
- stale scheduler frontier is rejected;
- debt beyond bounded catch-up budget is rejected;
- A13 Spatial, A13 Exact Worksets, A12 and A11 exact suites rerun on the same subject.

## Не входит в R1

- player/proximity/observer heuristic for activity classification;
- ACTIVE canonical progression ahead of sleeping debt;
- reduced/aggregate/patch biology;
- mathematically compressed multi-tick lifecycle integration;
- per-tile resource allocators;
- cross-tile interaction boundary approximation;
- thread-level parallelism;
- scheduler metadata persistence;
- population cap >256.

## Следующий architectural step

После R1 можно безопасно выбирать один из двух путей:

1. bounded parallel prepare/advance при сохранении каждого canonical tick; или
2. fidelity-aware FULL/REDUCED/PATCH sleeping, но только с явным contract для
   cross-tile resources/feedback и доказательством, что reduced catch-up не создаёт
   вторую ecology truth.

До этого момента утверждение «sleeping = просто не симулируем» запрещено.
