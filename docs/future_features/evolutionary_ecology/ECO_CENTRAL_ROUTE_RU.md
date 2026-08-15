# ECO — Центральный маршрут развития

Статус: `ACTIVE / VIS1 PRIORITY / RESEARCH_PRESENTATION`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

Visual proving ground plan: `docs/future_features/evolutionary_ecology/ECO_VIS1_VISUAL_PROVING_GROUND_PLAN_RU.md`.

## Решение о текущем приоритете

После закрытия branch-local P4 следующая практическая задача ECO — **сначала увидеть и измерить результат модели**, а не немедленно продолжать production integration.

Текущий маршрут:

```text
accepted ECO research + PH5 derived presentation
        ↓
P4 branch lifecycle COMPLETE
        ↓
ECO.VIS1 Visual Ecology Proving Ground       ← PRIORITY NOW
        ↓
ECO.VIS2 Causal Landscape Experiment
        ↓
ECO.XFER-VIS Real World Surface Adapter
        ↓
дальнейшая production integration уже на поверхности simulator
```

`control/eco-p4-production-convergence-prep-r1` / PR #108 сохраняется как готовая карта будущего production convergence. Она не отменена, но не является ближайшей практической целью.

## Почему VIS1 сейчас важнее

Модель уже содержит достаточно причинной ecology-логики и derived plant presentation, чтобы следующий риск был не «нам не хватает ещё одной формулы», а «мы плохо видим, что модель реально делает в пространстве и во времени».

VIS1 должен дать два синхронных представления одной ecology truth:

```text
canonical/research ecology state
       ├── numerical diagnostics
       └── derived PH5 visual presentation
```

Числа и картинка должны объяснять друг друга.

## VIS1 — ближайший этап

Первый полигон — bounded landscape примерно `500 x 500 m`, расширяемый до `1 x 1 km` без смены contracts.

Он не содержит canonical biome map. Вместо неё используются continuous causal fields:

- temperature;
- moisture;
- light;
- nutrients;
- altitude;
- slope;
- water availability/distance;
- seasonal inputs;
- disturbance state/history.

Разные участки должны отличаться только причинами среды и истории. Названия вроде «лес», «луг», «болото» допустимы только как human observation результата.

### Переносимая граница

```text
EcoEnvironmentProvider.sample(position) -> EnvironmentSample
```

VIS1 использует `LabEnvironmentProvider`.

Позже XFER-VIS заменяет его на `WorldEnvironmentProvider`, который читает реальную поверхность, воду, климат, material/resource projections и world history.

Ecology consumer не должна зависеть от того, какой provider используется.

### VIS1 steps

```text
VIS1.0  Lab scene + terrain + camera/operator movement
VIS1.1  EcoEnvironmentProvider + LabEnvironmentProvider
VIS1.2  spatial ecology snapshot projection
VIS1.3  accepted PH5 materialization on polygon
VIS1.4  time controls + same-seed restart
VIS1.5  numerical dashboard + time-series capture
VIS1.6  diagnostic overlays
VIS1.7  disturbances + event log
VIS1.8  0->200 year comparative acceptance experiment
```

## Что смотрим визуально

Нас интересуют не финальные красивые assets, а причинно читаемые различия:

- высота/форма растений;
- canopy/branch/foliage differences;
- плотность и biomass;
- локальная адаптация к environment;
- расселение;
- succession;
- coexistence/competitive displacement;
- disturbance/recovery;
- долгосрочное пространственное разделение communities.

PH5 остаётся derived presentation. Mesh/LOD никогда не становятся ecology truth.

## Что смотрим в числах

Для selected patch/region и для всего полигона нужны минимум:

- simulation year / generation;
- environment sample;
- population/cohort count;
- lineage count;
- total biomass;
- biomass by lineage;
- dominant share;
- recruitment/establishment/turnover, где доступны;
- resource pressure;
- coexistence/diversity diagnostics;
- disturbance/recovery progress;
- deterministic ecology/result hash.

Нужны временные ряды, чтобы видеть не только итог, но и путь к нему.

## Ускоренное время

Обязательные controls:

```text
PAUSE
1x
10x
100x
1000x
+1 year
+10 years
+100 years
```

Целевой операторский эксперимент — увидеть примерно `0 -> 200` игровых лет за минуты.

Ускоренный stepping обязан сохранять те же ecology semantics, что эквивалентный deterministic progression.

## Diagnostic overlays

```text
NORMAL
MOISTURE
TEMPERATURE
NUTRIENTS
LIGHT
WATER_AVAILABILITY
BIOMASS
POPULATION_DENSITY
LINEAGE
AGE/SUCCESSION
FITNESS/SUITABILITY
DISTURBANCE/RECOVERY
```

Overlay — derived read-only диагностика.

## Controlled disturbances

VIS1 должен позволять применять bounded лабораторные события:

- fire;
- drought;
- flood;
- cold/warm period;
- nutrient enrichment/depletion;
- local vegetation clearing.

Каждое событие записывается в deterministic event log с областью, силой и временем.

## VIS1 acceptance

VIS1 проходит, когда можно в одной operator session:

1. ходить/летать камерой над полигоном;
2. видеть vegetation и числовую ecology одного состояния;
3. ускорять время и видеть изменение community;
4. вызвать disturbance и проследить recovery/succession;
5. сравнить разные causal zones без biome/species table;
6. перезапустить same seed + same event log и получить те же ecology hashes;
7. переключать environment/ecology overlays;
8. подтвердить, что presentation не меняет ecology truth.

## VIS2

VIS2 делает landscape менее лабораторным:

- richer relief;
- drainage/water;
- continuous soil/resource fields;
- altitude-temperature coupling;
- slope/exposure;
- seasons;
- spatial disturbance history;
- multiple-seed comparison.

Главный вопрос VIS2: возникают ли устойчиво разные сообщества сами из environment + history.

## XFER-VIS

После VIS1/VIS2 переносим не «демо», а интерфейс:

```text
LabTerrain + LabEnvironmentProvider
              ↓
Real simulator surface + WorldEnvironmentProvider
```

Первая production-like цель — один реальный surface region около `1 x 1 km`, не вся планета.

На этом этапе уже используются ограничения из PR #108: ECO не создаёт вторую persistence, authority, World Query, lifecycle/work-budget или network truth.

## Ownership / non-goals

VIS track не владеет:

- terrain/geology truth;
- production persistence durability;
- server/cross-server authority;
- World Query;
- lifecycle/work-budget foundations;
- material ontology;
- network replication policy.

Полигон нужен для исследования, объяснимости и presentation feedback. Production port начинается только после того, как результат ECO нас устраивает визуально и численно.
