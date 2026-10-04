# EVO ARCH2 — Roadmap R4

Статус: CURRENT ROADMAP.

## Train

| Этап | Результат |
|---|---|
| A0–A10 | canonical evolvable ecology + world bindings |
| A10.5 | ECO-POLYGON-1 experiment/replay workbench |
| A11 | visible persistent evolving habitat — CLOSED |
| A12 | multi-generation population scale 256/256 — CLOSED |
| **A13** | **Population Scaling Architecture** |

## A13 — Population Scaling Architecture

A12 доказал реальную многопоколенную ecology на canonical population ceiling 256.
A13 меняет не biology, а форму исполнения.

### R1 — Deterministic Exact Worksets

```text
canonical population
        ↓
stable id ordering
        ↓
worksets of 64
        ↓
prepare/sample/demands per workset
        ↓
ONE GLOBAL RESOURCE ALLOCATION
        ↓
advance per workset
        ↓
canonical merge
        ↓
same hashes / same checkpoint
```

Acceptance:
- 256 members покрыты worksets ровно один раз;
- input permutation не меняет plan;
- invalid/tampered plan rejected;
- A5 size 1 / 64 / 256 даёт одинаковые field/population/propagule results;
- shared Runtime при разных workset sizes даёт одинаковый state hash каждый tick;
- reproduction/mutation продолжаются через canonical A5/A3;
- checkpoint bytes идентичны;
- workset config не записывается как biological state;
- A12/A11 regressions остаются green.

### Следующие ступени A13

После R1:
1. spatial workset addressing;
2. active/sleeping population scheduling;
3. bounded parallel prepare phase;
4. bounded parallel post-allocation advance;
5. fidelity-aware FULL/REDUCED/PATCH scheduling;
6. profiling и scheduler telemetry;
7. отдельная совместимость с historical A6 replay-wrapper;
8. новый scale increment >256 только после evidence.

A13 запрещено превращать в независимые per-chunk simulations с отдельным resource allocation — это изменило бы ecological causality.
