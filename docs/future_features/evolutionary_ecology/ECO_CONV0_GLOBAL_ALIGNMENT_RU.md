# ECO.CONV0 — Global Alignment / World Integration Consumer Requirements

Статус: `ACTIVE DESIGN CONTRACT / RESEARCH_ONLY / NO RUNTIME OWNERSHIP`.

## Почему этот этап сейчас

На момент принятия ECO.PH глобальный `main` уже содержит normal merge PR #90 / H0.1 R8 / C22 at `eefd75fa3badec10c6e7db959e2a3992dba30f0e`.

При этом main-owned registry generation 77 и human CURRENT snapshot ещё описывают pre-C22 состояние. Это означает, что точный глобальный operational state должен быть пересинхронизирован post-C22 через Project Control; ECO не имеет права использовать старый registry text как authorization для production integration.

Глобальная North Star:

> persistent seamless distributed world simulator where construction, terrain, matter, characters and multiplayer authority compose without duplicate truth layers.

Ключевые dimensions, непосредственно относящиеся к ECO:

- canonical truth integrity;
- seamless scale;
- incremental representation;
- parallel program convergence.

ECO.PH уже закрыл representation часть: `identity != LOD`, individual geometry disposable, far state может существовать без materialized individual GrowthGraph.

Следующий полезный вклад ECO в глобальную архитектуру — не новый runtime manager и не private world state, а **consumer requirements** к будущим canonical foundations.

## Глобальный критический путь, который ECO не должен блокировать

```text
C22 merged into main
        ↓
post-C22 validation + standard/directional PC0 + control sync
        ↓
GLOBAL-P0 R3 exact-current-main repin
        ↓
HUMAN GLOBAL_ARCHITECTURE_PROMOTION
        ↓
post-R3 PC0
        ↓
H0.2 / NX.C1
```

R3 candidate сохраняет cross-domain foundations `SD`, `TF`, `MAT`, `WT`, `WQ`, `LIFE`, `WB` и другие. Wave A после promotion предполагает как минимум `MAT0`, `WT0`, `WQ0/WQ1` рядом с identity/auth foundations.

ECO остаётся advisory/research и не входит в этот runtime critical path.

## Тактическое решение после PH5

Старый fork `CONV0 | CAL1` уточняется без изменения его смысла:

```text
ECO.PH RESEARCH COMPLETE
          ↓
      CONV0-A NOW
consumer requirements / ownership matrix
          ↓
   ┌──────┴──────────────┐
   ▼                     ▼
 CAL1                 wait canonical R3
   │                     │
   ▼                     ▼
  P2                 CONV0-B freeze
   │                     │
   └──────────┬──────────┘
              ▼
     WAIT FOR FOUNDATIONS
              ↓
             P3
              ↓
             PH6
```

`CONV0-A` должен быть коротким: он формулирует требования ECO к global foundations до их freeze, чтобы ecology не обнаружила архитектурный пробел слишком поздно.

После `CONV0-A` основной research effort переходит в `CAL1`, потому что именно CAL1 блокирует честное unrestricted morphology evolution и P2.

`CONV0-B` — финальная привязка ECO-side contracts к реальным canonical R3/WQ/MAT/LIFE/WB contracts — выполняется только после их появления. До этого нельзя invent private substitutes.

## CONV0-A — что определить

### 1. Ownership matrix

ECO должен описать только consumer/producer semantics относительно:

- `SD / Spatial Domain Fabric` — где находится ecology patch/domain; ECO не создаёт WorldAddress или новый ChunkId;
- `TF / Time Fabric` — simulation time/history windows/multi-rate update requirements; ECO не создаёт global clock;
- `WQ / World Query Fabric` — как получить environmental projection; ECO не создаёт canonical query engine/store;
- `MAT / Material Ontology` — как получить substrate/material properties; ECO не создаёт private rock/soil/material identity;
- `LIFE / Promotion-Dormancy-Demotion` — когда aggregate population detail может стать promoted individual detail и обратно;
- `WB / World Work Budget` — как ecology предлагает bounded work; ECO не создаёт scheduler/authority;
- `NX8 / interest-replication budget` — как передавать population/domain truth вместо каждого растения;
- `WT / World Transaction semantics` — только будущая граница для cross-domain player/world effects, не новая transaction implementation.

### 2. EcoEnvironmentQueryRequirements

Нужно определить требования к входу, но не реализацию WQ API:

```text
WorldAddress/domain scope
simulation time / history window
query revision/provenance
        ↓
temperature
moisture
sunlight
nutrients
flood/water stress
disturbance/history
substrate/material projection
```

Должно быть возможно отличить:

`query result revision != ecology state revision`.

### 3. EcoPopulationProjectionRequirements

Derived output ECO для presentation/network/diagnostics должен уметь выражать aggregate state без planet-wide individual objects:

```text
population/lineage identity reference
patch/domain reference
population count / density
biomass
seed-bank / recruitment summary
phenotype/development distribution
health/stress distribution
representation hints
promotion candidates / interaction relevance hints
provenance/revision
```

Важно: это **requirements shape**, а не новый canonical population store.

Идея bounded synthetic visual sampling из отклонённого overlap `74aedd27` сохраняется только как возможная derived representation strategy. Она не является canonical organism list и не входит в accepted PH5 API.

### 4. Promotion boundary

Нужно сформулировать state transition contract:

```text
aggregate population truth
        ↓ observation / interaction / damage / ownership relevance
promoted individual detail
        ↓ dormancy/demotion
aggregate-compatible retained delta / population truth
```

Запрещено:

- считать `Node3D` существованием организма;
- создавать planet-wide GrowthGraph truth;
- связывать LOD с identity;
- удалять canonical organism только потому, что representation dematerialized.

### 5. Work/budget requirements

ECO должен уметь предлагать работу примерно в форме:

```text
domain scope
simulation interval
input revisions
estimated cost
priority/relevance
result revision/provenance
```

Но решение `run/defer/split` принадлежит canonical Work Budget/Harness/runtime foundations, не ECO.

### 6. Network/interest projection

Default principle:

```text
server population/domain truth
        ↓
client deterministic/derived representation
```

Individual replication появляется только после explicit promotion/interaction relevance. `NX8` остаётся владельцем shared interest/replication budget policy.

## CONV0-A acceptance

Этап можно считать завершённым, когда есть:

1. machine-readable ECO consumer-requirements contract;
2. ownership matrix `ECO concept -> canonical owner -> ECO usage -> forbidden local ownership`;
3. explicit environment-query required fields + provenance rules;
4. aggregate population projection required fields + identity rules;
5. promotion/dormancy/demotion requirements;
6. work-budget and network/interest requirements;
7. compatibility review против актуального R3 candidate;
8. список gaps, которые нужно передать R3/WQ/MAT/LIFE/WB owners;
9. доказательство, что никакой production/runtime foundation не реализован.

## Stop rule CONV0-A

До canonical R3 и соответствующих foundation contracts запрещено:

- создавать production `EcoEnvironmentQuery` adapter;
- создавать ECO-private WorldAddress/spatial cell identity;
- создавать ECO-private MaterialDefinition/soil ontology;
- создавать authority/persistence/transport layer;
- создавать global ecology scheduler/work budget;
- фиксировать production network replication protocol;
- начинать P3/PH6.

## После CONV0-A

Основная исследовательская цель ветки:

`ECO.CAL1 — Morphology Economics Calibration`.

CAL1 должен закрыть наблюдаемый `HEIGHT_LOW/full-pool dominance` через missing-mechanism causal experiments, а не косметическую подгонку коэффициентов. После CAL1 открывается `ECO.P2 Dispersal / Recruitment / Biogeography`.

Параллельно, когда R3 + WQ/MAT/LIFE/WB contracts станут canonical, выполнить `CONV0-B` compatibility/freeze и только затем рассматривать будущий controlled P3 runtime frontier.
