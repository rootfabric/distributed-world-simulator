# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-A EXECUTE_NOW`.

Canonical North Star:

`docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine vision:

`config/ecology/eco-evolutionary-ecosystem-vision.v1.json`.

## 1. Что строит эта ветка

ECO — самостоятельный evolutionary-ecology mini-project внутри Distributed World Simulator.

Его конечная задача:

> взять ландшафт и initial ancestry, автономно вырастить на нём экологию без hardcoded biome/species placement, сохранить spatial/history state, а позднее позволить World Simulator материализовать и продолжить ту же экологию локально и в background.

Ветка не стремится напрямую к «красивым деревьям» или к раннему runtime integration.

## 2. Три слоя

```text
A. EVOLUTIONARY ECOSYSTEM
   standalone / headless / no player required
                ↓
B. SIMULATOR LIVING ECOLOGY
   import/query/activate/background continuation
                ↓
C. DERIVED PRESENTATION
   mesh / assets / animation / LOD
```

PH5 относится к слою C и уже дал достаточно representation foundation для текущего research stage.

Основная работа теперь возвращается в слой A.

## 3. Один ecological state, три режима исполнения

```text
INCUBATE_FAST
    accelerated long-horizon evolution

BACKGROUND_COARSE
    region/planet lives without observer

LOCAL_ACTIVE
    active local simulation and interaction
```

Ключевая инварианта:

`execution resolution != different ecology truth model`.

Offline evolution и runtime continuation не должны разойтись в две независимые системы правил.

## 4. Уже принято

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH4              ACCEPTED
ECO.PH5-S1..S4            ACCEPTED
ECO.PH representation     RESEARCH COMPLETE
ECO.CONV0-A               ACCEPTED DESIGN REQUIREMENTS
```

CONV0-A показал, что future simulator bridge должен использовать canonical `G/ENV/MAT/WQ/SD/TF/POP/LIFE/WB/NX/WT` foundations, а не ECO-private substitutes.

## 5. Новый центральный маршрут

```text
FOUNDATION ACCEPTED
P1 + PH0..PH5-S4
        │
        ▼
EVO0 — PLANT CAUSAL ECOLOGY
CAL1 ← CURRENT
morphology economics / missing mechanisms
        │
        ▼
EVO1 — PLANT WORLD PROOF
P2 dispersal / recruitment / seed bank /
succession / disturbance / migration /
biogeography / lineage divergence
        │
        ▼
EVO2 — LONG-RUN EVOLUTIONARY LANDSCAPE
history / isolation / extinction-recolonization /
dynamic attractors / save-restart / ecology epochs
        │
        ▼
EVO3 — MULTI-TROPHIC ECOSYSTEM
organic matter + decomposers
        ↓
plant ↔ herbivore
        ↓
plant ↔ herbivore ↔ predator
        ↓
coevolution
        │
        ▼
EVO4 — AUTONOMOUS REGIONAL / PLANET ECOLOGY
headless runner
INCUBATE_FAST + BACKGROUND_COARSE
        │
        ▼
XFER0 — PORTABLE ECOLOGY ARCHIVE
state + lineage catalog + spatial atlas + history
        │
        ├──────────── wait canonical simulator foundations
        │
        ▼
XFER1 — WORLD GENERATION BRIDGE
G/MAT/ENV → ecology projection → local materialization
        │
        ▼
LIVE1 — LOCAL ACTIVE ECOLOGY
        │
        ▼
LIVE2 — BACKGROUND/OFFSCREEN CONTINUATION
+ coarse/fine convergence
        │
        ▼
LIVE3 — WORLD/PLAYER DISTURBANCE FEEDBACK
        │
        ▼
PRES1+ — richer derived visuals later
```

## 6. EVO0 — текущая работа

`ECO.CAL1` остаётся текущим checkpoint.

Но его роль уточнена:

```text
CAL1 != цель ECO
CAL1 = hardening plant economics before autonomous ecosystem proof
```

Current:

`CAL1-A Baseline Decomposition / Mechanism Audit`.

Далее:

- CAL1-B relative vertical light competition;
- CAL1-C crown/root competition;
- CAL1-D lifetime/reproduction/dispersal/disturbance payoffs;
- CAL1-E combined mechanisms;
- CAL1-F calibration/full-pool robustness.

После CAL1 не продолжать morphology tuning ради tuning.

## 7. EVO1 — следующий главный milestone

Новый target:

`ECO.EVO1_PLANT_WORLD_PROOF`.

Нужно взять небольшой детерминированный неоднородный landscape, общий ancestral pool и доказать:

- никакой biome->species placement table;
- seed dispersal создаёт реальное spatial propagation;
- establishment зависит от local conditions;
- competition меняет состав сообщества;
- seed bank и recruitment дают continuity;
- succession возникает из механики, не state machine;
- disturbance меняет trajectory;
- isolation/migration создают различия между patches;
- long run не runaway-collapse/explosion;
- save/restart сохраняет ecology history;
- lineages начинают занимать разные ecological niches.

P2 теперь является execution plan внутри EVO1, а не просто мостом к production P3.

## 8. EVO2 — история и эволюция ландшафта

После plant-world proof расширить масштаб времени/пространства:

- ecology epoch/time;
- multiple connected/isolated regions;
- migration flux;
- local extinction/recolonization;
- historical contingency;
- lineage tracking;
- dynamic attractors;
- speciation candidate diagnostics;
- deterministic replay/provenance.

Цель: одинаковая среда с разной историей может иметь разную экологию.

## 9. EVO3 — животные и прочая органика

Животные добавляются только после устойчивого plant substrate.

Не вводить hardcoded `Rabbit eats Grass01`.

Пищевые связи должны следовать из свойств:

```text
food biomass / chemistry / digestibility
consumer metabolism / diet / mobility / defense
reproduction / predation / territory
```

Первый порядок:

1. decomposition / organic-matter loop;
2. herbivore population;
3. predator population;
4. multi-trophic robustness;
5. coevolution experiments.

Detailed fauna meshes/animation не являются acceptance requirement.

## 10. EVO4 — автономный Ecology Runner

ECO должен реально запускаться отдельно от игрового клиента.

Обязательные режимы:

- `INCUBATE_FAST` — accelerated evolution;
- `BACKGROUND_COARSE` — living ecology without player;
- pause/save/restart;
- deterministic seeded run;
- bounded population/cohort representation;
- diagnostics/dashboard достаточный для research.

Это и делает ветку самостоятельным mini-project.

## 11. XFER0 — EcologyArchive

Переносимый результат должен включать не только SpeciesCatalog.

Минимально:

```text
EcologyWorldState snapshot
+ lineage catalog
+ spatial population atlas
+ biomass/density/age distributions
+ seed/recruitment state
+ disturbance/history state
+ ruleset/provenance/replay metadata
```

`EcologyArchive` позволяет взять экологию конкретной планеты и воспроизводимо материализовать её в симуляторе.

## 12. XFER1 — bridge в G / world generation

Только после готовности canonical simulator foundations.

Целевая зависимость:

```text
G / MAT / ENV
terrain + substrate + environment
           ↓
EcologyArchive / EcologyWorldState
           ↓
EcologyLocalProjection
           ↓
local placement/materialization
```

ECO определяет экологическую occupancy/distribution.

G/MAT/ENV продолжают владеть terrain/geology/material/environment truth.

Rock placement не является ecology responsibility.

## 13. LIVE — продолжение той же экосистемы

При активации участка:

```text
EcologyPatchState
      ↓
LocalEcologyState
      ↓
promoted plants/animals when necessary
      ↓
interaction / growth / feeding / reproduction / damage
      ↓
aggregate result
      ↓
EcologyPatchState
```

При уходе игрока ecology не исчезает — patch возвращается в background/coarse execution.

Нельзя иметь одну independent offline ecology и вторую unrelated runtime ecology для одной canonical planet state.

## 14. Presentation

Текущего PH5 достаточно как proof того, что visual representation derived.

До завершения ECO/EVO major proofs не приоритизировать:

- photorealistic vegetation;
- complex procedural leaf assets;
- animal animation system;
- final art pipeline.

Позже presentation может стать отдельным track и свободно улучшаться поверх ecology state.

## 15. Глобальные gates

Standalone `EVO0..EVO4` можно развивать независимо от runtime critical path основного проекта.

`XFER1/LIVE` ждут canonical foundations и Harness-controlled runtime frontier.

CONV0-A findings остаются действующими, включая:

- `ECO` должен означать Evolutionary Ecology; future economy — `ECON`;
- generic production population fabric остаётся `POP`-owned;
- ECO не создаёт private WQ/SD/TF/MAT/LIFE/WB/NX/WT/persistence/authority foundations.

## 16. Операционный resolver

При команде «продолжай ECO»:

1. прочитать North Star vision;
2. прочитать machine roadmap;
3. выполнить `current_step`;
4. не перескакивать в XFER/LIVE до gates;
5. после каждого acceptance проверять, приближает ли следующий этап к автономной экосистеме, а не только к локальному subsystem sophistication.

Сейчас resolver однозначен:

`ECO.CAL1-A EXECUTE_NOW`.
