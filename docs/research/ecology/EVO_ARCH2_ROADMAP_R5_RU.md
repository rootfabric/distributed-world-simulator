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
| **A13 Activity** | **Active / Sleeping Population Scheduling — CURRENT** |

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

### ▶ Active / Sleeping Population Scheduling — R1 exact cadence

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

### Следующие ступени A13

1. ✅ deterministic exact worksets;
2. ✅ spatial workset addressing;
3. ▶ active/sleeping population scheduling — exact cadence R1;
4. ⬜ bounded parallel prepare;
5. ⬜ bounded parallel post-allocation advance;
6. ⬜ fidelity-aware FULL/REDUCED/PATCH scheduling;
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
