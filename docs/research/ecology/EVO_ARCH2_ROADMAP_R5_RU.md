# EVO ARCH2 — Roadmap R5

Статус: CURRENT ROADMAP.

## Train

| Этап | Результат |
|---|---|
| A0–A10 | canonical evolvable ecology + world bindings |
| A10.5 | ECO-POLYGON-1 experiment/replay workbench |
| A11 | visible persistent evolving habitat — CLOSED |
| A12 | multi-generation population scale 256/256 — CLOSED |
| A13 R3 | deterministic exact worksets — CLOSED |
| A13 Spatial | Spatial Workset Addressing — CLOSED |
| A13 Activity | Active / Sleeping Population Scheduling — CLOSED |
| A13 Parallel Prepare | Bounded Parallel Prepare — CLOSED |
| A13 Parallel Advance | Bounded Parallel Advance — CLOSED |
| **A13 Fidelity Scheduling** | **FULL / REDUCED / PATCH — CURRENT** |

## A13 Population Scaling Architecture

### ✅ Foundation — Deterministic Exact Worksets

Closed invariant:

canonical population
→ bounded worksets
→ prepare
→ ONE GLOBAL RESOURCE ALLOCATION
→ advance
→ canonical merge
→ same hashes/checkpoints

### ✅ Spatial Workset Addressing

Spatial scheduler address is derived, never authoritative:

position_mm + field geometry
→ spatial tile address
→ bounded deterministic shard

Closed invariant:
- stable derived addresses;
- no duplicate/missing population coverage;
- deterministic sharding;
- migration makes previous plan stale;
- no address persisted in organism/runtime/checkpoint;
- same global resource allocation barrier;
- spatial execution exact-equivalent to closed exact worksets;
- reproduction/mutation/checkpoints remain byte-identical.

### ✅ Active / Sleeping Population Scheduling — R1 exact cadence

R1 вводит scheduler-only activity classification и deterministic cadence поверх
stable spatial addresses:

spatial tile
→ activity classifier
├─ ACTIVE
└─ SLEEPING
    ↓
deterministic cadence debt
    ↓
exact full-frontier catch-up
    ↓
same canonical ecology truth

Ключевой R1 invariant:

- activity/cadence metadata не входит в canonical Runtime/checkpoint;
- ACTIVE cadence = 1, SLEEPING cadence задаётся детерминированно;
- пока sleeping cadence не наступил, mixed-world canonical state не продвигается;
- на wake replay-ится каждый пропущенный canonical tick;
- каждый replay tick заново строит spatial worksets;
- каждый replay tick сохраняет ONE GLOBAL RESOURCE ALLOCATION;
- catch-up обязан быть byte/hash-identical continuous execution;
- partial catch-up не публикуется при ошибке.

Причина строгого поведения R1: общий Field allocator связывает resource grants всех
организмов. Нельзя канонически продвинуть ACTIVE tiles без sleeping demands, а потом
догнать только sleeping, не меняя ecological causality.

R1 — reference exact semantics и фундамент для будущего sleeping fidelity. Это ещё
не mixed ACTIVE/SLEEPING performance optimization.


### ✅ Bounded Parallel Prepare — R1

A5 Phase 1 preparation becomes bounded-parallel over the existing deterministic
spatial worksets:

```text
spatial worksets
→ bounded worker waves
→ per-workset phenotype/sample/demand preparation
→ join all workers
→ canonical merge by workset index
→ ONE GLOBAL RESOURCE ALLOCATION
→ serial canonical post-allocation advance
```

R1 invariant:

- worker completion order is never canonical order;
- worker bound is explicit and <= 8;
- each worker owns deep-copied input and local output;
- every worker must execute off the main thread;
- all workers join before global allocation;
- demands merge in the same order as serial spatial scheduling;
- exactly one global allocation remains authoritative;
- post-allocation advance is still serial in this stage;
- thread/scheduler telemetry is absent from Runtime/checkpoints;
- serial and parallel paths must be byte/hash/checkpoint exact-equivalent on Windows and Linux.

R1 is a correctness + concurrency foundation. Performance claims require the later
profiling/telemetry stage.

### ✅ Bounded Parallel Advance — R1

Поверх закрытого parallel-prepare добавляется второй bounded worker phase после
единственного глобального resource-allocation barrier:

```text
parallel prepare
→ join
→ ONE GLOBAL Field.allocate_demands()
→ parallel per-workset _advance_individual()
→ join
→ canonical workset/member merge
→ canonical population / propagules
```

Инварианты R1:

- ни один advance worker не стартует до успешной global allocation;
- allocator остаётся единственным и вызывается один раз;
- advance worker не владеет Field и не пишет в canonical Runtime;
- вход worker — deep-copied entry/sample/grant;
- completion order не влияет на result order;
- failures принимаются только в canonical workset order;
- global propagule limit проверяется при canonical merge;
- prepare и advance worker bounds независимы и ограничены 1..8;
- serial / parallel-prepare / full-parallel обязаны быть byte/hash/checkpoint exact-equivalent;
- Activity catch-up остаётся exact.

R1 не заявляет ускорение до отдельного profiling/telemetry checkpoint.

### ▶ Fidelity-Aware FULL / REDUCED / PATCH Scheduling — R1

Следующий слой наследует уже принятые A9 fidelity semantics и накладывает их
на A13 spatial scheduler без второго biological kernel:

```text
spatial address
→ FULL / REDUCED / PATCH
→ one global canonical frontier

FULL:
  exact history retained, cadence 1

REDUCED:
  exact history retained losslessly
  → bounded defer
  → complete exact replay through Parallel Advance

PATCH:
  lossy authenticated projection, historical individuals absent
  → bounded defer
  → at due boundary: REFINEMENT_REQUIRED
  → zero canonical mutation
  → after external exact refinement caller explicitly reclassifies to FULL/REDUCED
```

R1 invariants:

- FULL/REDUCED/PATCH are scheduler/representation choices, not new biology owners;
- REDUCED is not approximate dynamics: wake replays every missed exact tick;
- PATCH cannot execute exact ecology and never reconstructs individuals from totals/cohorts;
- one global A5 allocator still couples all tiles, therefore FULL cannot commit ahead of REDUCED/PATCH debt;
- no independent per-tile canonical timeline;
- no partial catch-up publish;
- every exact replay tick uses the verified Parallel Advance path;
- fidelity metadata never enters Runtime/checkpoints;
- unknown/tampered/stale fidelity plans fail closed;
- PATCH refinement is explicit and caller-owned;
- AGGREGATE remains report-only and is not a scheduling mode;
- performance claims remain deferred to profiling/telemetry.

### Следующие ступени A13

1. ✅ deterministic exact worksets;
2. ✅ spatial workset addressing;
3. ✅ active/sleeping population scheduling — exact cadence R1;
4. ✅ bounded parallel prepare;
5. ✅ bounded parallel post-allocation advance;
6. ▶ fidelity-aware FULL/REDUCED/PATCH scheduling;
7. ⬜ profiling / scheduler telemetry;
8. ⬜ historical A6 replay-wrapper compatibility;
9. ⬜ evidence-backed scale increment >256.

Запрещено:
- независимые per-tile simulations;
- отдельный resource allocator на tile;
- scheduler metadata как biology truth;
- скрытая потеря организмов при migration/sharding;
- считать `sleeping = не симулируем` без explicit reduced-fidelity contract;
- публиковать ACTIVE canonical truth впереди sleeping debt в exact R1.
