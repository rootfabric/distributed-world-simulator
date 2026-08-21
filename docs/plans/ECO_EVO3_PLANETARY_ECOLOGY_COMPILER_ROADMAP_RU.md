# ECO.EVO3 — Planetary Ecology Compiler — Research Roadmap R1

Статус: `RESEARCH_ONLY / E3.0 ACCEPTANCE CANDIDATE / E3.1 NEXT`.

Architecture: `docs/architecture/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ARCHITECTURE_RU.md`.
Machine architecture: `config/ecology/eco-evo3-planetary-ecology-compiler.v1.json`.
Machine roadmap: `config/ecology/eco-evo3-roadmap.v1.json`.

## Маршрут

```text
E3.0  Planetary Ecology Compiler Architecture & Roadmap
      ACCEPTED after exact static validation
        ↓
E3.1  Planet Field Snapshot Contract
        ↓
E3.2  Ecological Opportunity Field
        ↓
E3.3  Research Ecology Decomposition
        ↓
E3.4  Causal Colonization Program Compiler
        ↓
E3.5  Multi-scale Population Workset Compiler
        ↓
E3.6  Seasonal & Disturbance Temporal Program
        ↓
E3.7  Deterministic Planet Compilation
        ↓
E3.8  Cross-Planet Generalization Matrix
        ↓
E3.FINAL  Planetary Ecology Compiler Challenge
```

Работа последовательная: checkpoint нельзя пропускать или активировать до принятия предшественника. Post-freeze executable/static semantic drift требует нового target и повторной проверки.

## E3.0 — Architecture & Roadmap

Замораживает `PlanetEcologyProgram`, seven-stage compiler DAG, truth model, deterministic rules, scale semantics и authority barriers. Никакой production binding/runtime activation.

## E3.1 — Planet Field Snapshot Contract

Research-only adapter/fixture для snapshot-bound семантики `G/ENV/MAT/WQ/SD/TF` без изобретения production API. Требуется stable planet/spatial/time/reference-frame identity и field provenance.

## E3.2 — Ecological Opportunity Field

Строит continuous causal opportunity fields из owner-provided fields. Запрещено выдавать species assignment/biome species labels. Suitability не является population truth.

## E3.3 — Research Ecology Decomposition

Строит deterministic research region/patch graph по environmental continuity/connectivity. Region IDs имеют research namespace и не являются canonical `SD` domains.

## E3.4 — Causal Colonization Program Compiler

Использует полный portable catalog, connectivity и causal dispersal/establishment semantics. Null/no-colonization — валидный результат; target-aware species injection и guaranteed colonization запрещены.

## E3.5 — Multi-scale Population Workset Compiler

Компилирует work units для `PLANET / REGION / PATCH / LOCAL_ACTIVE` и budget hints, сохраняя один ecology state meaning. Planet-wide individual entity truth запрещён.

## E3.6 — Seasonal & Disturbance Temporal Program

Компилирует snapshot-bound temporal/disturbance envelopes. ECO не становится owner `TF` или `ENV` и не переписывает canonical history.

## E3.7 — Deterministic Planet Compilation

Fresh-process compilation полного planet fixture должна быть byte/hash stable для одинаковых snapshots + catalog. Global RNG запрещён; все external nondeterministic inputs snapshot-bound.

## E3.8 — Cross-Planet Generalization Matrix

Predeclared planet families: dry, wet, cold, hot, high-seasonality и topologically-isolated. Нельзя retune catalog/compiler после reveal. Null/reversal/no-colonization outcomes сохраняются.

## E3.FINAL — Planetary Ecology Compiler Challenge

Persisted EVO2 catalog + precommitted unseen planet fields → deterministic causal `PlanetEcologyProgram`/evidence без rebake, biome species tables, target-aware species injection или asset scatter truth.

## XFER1 boundary

Research EVO3 разрешён поверх XFER0 semantic contract. Production binding остаётся заблокирован:

```text
XFER1 = BLOCKED_WAIT_CANONICAL_FOUNDATIONS
required = G / ENV / MAT / WQ / SD / TF
```

Только owner-approved canonical contracts могут открыть production-facing binding. EVO3 research evidence не является production authorization.

## После EVO3

После plant-only planetary compiler proof можно проектировать plant runtime convergence и затем EVO4 multi-trophic ecology. Животные/food-web не должны опережать plant planetary generalization proof.
