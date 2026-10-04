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
| **A13 Spatial** | **Spatial Workset Addressing — CURRENT** |

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

### ▶ Spatial Workset Addressing

Spatial scheduler address is derived, never authoritative:

position_mm + field geometry
→ spatial tile address
→ bounded deterministic shard

Acceptance:
- stable derived addresses;
- no duplicate/missing population coverage;
- deterministic sharding;
- migration makes previous plan stale;
- no address persisted in organism/runtime/checkpoint;
- same global resource allocation barrier;
- spatial execution exact-equivalent to closed exact worksets;
- reproduction/mutation/checkpoints remain byte-identical.

### Следующие ступени A13

1. ✅ deterministic exact worksets;
2. ▶ spatial workset addressing;
3. ⬜ active/sleeping population scheduling;
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
- скрытая потеря организмов при migration/sharding.
