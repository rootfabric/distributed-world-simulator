# ECO.VIS1 — Visual Ecology Proving Ground

Статус: `PRIORITY_NEXT / RESEARCH_PRESENTATION / NOT_PRODUCTION_INTEGRATION`.

## Решение

Следующая практическая цель ECO — не дальнейшее углубление production-convergence и не немедленное встраивание в глобальную генерацию мира, а отдельный визуально-числовой полигон.

Цель полигона: дать возможность одновременно **видеть** и **измерять**, что реально делает накопленная ecology-модель: расселение, конкуренцию, succession, disturbance/recovery, локальную адаптацию и изменение пространственной структуры во времени.

После того как поведение на полигоне станет понятным и убедительным, сам полигонный интерфейс должен быть перенесён в основной simulator surface. Поэтому VIS1 обязан использовать переносимые boundaries, а не одноразовую demo-логику.

## Приоритетная последовательность

```text
ECO P4 branch lifecycle COMPLETE
        ↓
ECO.VIS1 Visual Ecology Proving Ground      ← PRIORITY NOW
        ↓
ECO.VIS2 Causal Landscape Experiment
        ↓
ECO.XFER-VIS Real World Surface Adapter
        ↓
дальнейшая production integration уже внутри simulator
```

Текущий `control/eco-p4-production-convergence-prep-r1` и PR #108 сохраняются как подготовленная карта будущего production-port, но runtime transfer P4.4/P4.5 не является ближайшей практической целью VIS1.

## Главная архитектурная граница

Полигон не должен сам определять биомы или виды через таблицы.

Он предоставляет причинные поля среды:

```text
position
  ↓
EnvironmentSample
  ├─ temperature
  ├─ moisture
  ├─ light
  ├─ nutrients
  ├─ altitude
  ├─ slope
  ├─ water_availability / water_distance
  ├─ disturbance state/history
  └─ season/time inputs
```

ECO использует эти значения и сама формирует population/community outcome.

Нужна переносимая граница вида:

```text
EcoEnvironmentProvider.sample(position) -> EnvironmentSample
```

Для VIS1:

```text
LabEnvironmentProvider
```

Позже в simulator:

```text
WorldEnvironmentProvider
    ↓
G / terrain / water / ENV / MAT / climate / world history
```

ECO consumer logic не должна зависеть от конкретного provider.

## Размер и форма первого полигона

Рекомендуемый диапазон: `500 x 500 m` для первой итерации, с возможностью перейти к `1 x 1 km` без смены семантики.

На одной территории должны присутствовать различающиеся причинные условия:

- влажная низина;
- сухой склон;
- возвышенность;
- плодородная равнина;
- бедный ресурсами участок;
- берег/водный градиент;
- disturbance zone.

Это не канонические биомы. Подписи `wetland`, `meadow`, `forest` могут использоваться только как post-hoc human observations результата.

## Что должно быть видно

VIS1 использует уже принятую derived presentation архитектуру PH5:

```text
Ecology/phenotype state
   ↓
GrowthGraph / PlantRenderDescription
   ↓
RendererProfile / Multi-Scale Representation
   ↓
Godot geometry
```

Не создавать второй renderer truth.

Минимально визуально должны различаться:

- высота растения;
- радиус/форма кроны;
- толщина/форма ствола и ветвей;
- foliage amount;
- общая биомасса/плотность сообщества;
- различия фенотипа от среды;
- разные стадии succession;
- recovery после disturbance.

Красота финального asset-quality не является gate VIS1. Цель — причинно читаемая визуальная обратная связь.

## Время

Полигон обязан поддерживать ускоренное исследование:

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

Практический сценарий: пройти примерно `0 -> 200` игровых лет за минуты, не ожидая wall-clock duration.

Ускорение не должно менять семантику результатов относительно эквивалентного deterministic stepping.

## Числовая панель

Рядом с визуальной сценой нужны числовые показатели минимум по выделенному региону/patch:

- simulation year / ecology generation;
- population/cohort count;
- lineage count;
- total biomass;
- biomass per lineage;
- seed/recruitment/establishment counters, где доступны;
- mortality/turnover;
- resource pressure;
- niche/coexistence diagnostics;
- disturbance/recovery progress;
- diversity proxy;
- dominant lineage share;
- current environment sample;
- deterministic state/result hash для контрольных снимков.

Для временных рядов достаточно простых графиков/таблиц; они являются derived diagnostics, а не canonical truth.

## Diagnostic overlays

Переключаемые overlay modes:

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
AGE / SUCCESSION_STAGE
FITNESS / SUITABILITY
DISTURBANCE / RECOVERY
```

Overlay должен читать те же EnvironmentSample/ecology snapshots, что и числовая панель.

## Интерактивные эксперименты

Нужны bounded operator actions на лабораторном provider/state:

- Fire;
- Drought;
- Flood;
- Cold period;
- Warm period;
- Nutrient enrichment/depletion;
- Clear vegetation / local reset.

Каждое событие должно иметь явный центр/область, величину и временной интервал и попадать в журнал эксперимента.

## Повторяемость

VIS1 должен позволять:

```text
Restart same seed
Restart new seed
Save lab checkpoint
Load lab checkpoint
```

Для одинакового seed + одинакового event log + одинакового time stepping должны совпадать canonical ecology hashes/diagnostics. Визуальный renderer остаётся derived.

## VIS1 acceptance

VIS1 считается успешным, когда один operator session позволяет:

1. запустить полигон и свободно осмотреть его камерой/персонажем;
2. увидеть одну и ту же ecology truth одновременно визуально и через numerical diagnostics;
3. ускорить время и наблюдать пространственное изменение сообщества;
4. применить disturbance и увидеть количественную и визуальную recovery/succession;
5. сравнить разные environmental zones без biome/species lookup tables;
6. повторить same-seed experiment и получить те же ecology hashes;
7. переключать diagnostic overlays;
8. подтвердить, что PH5 presentation остаётся derived и не мутирует ecology state.

## VIS2

После VIS1 расширяем полигон до `ECO.VIS2 Causal Landscape Experiment`:

- более естественный relief;
- вода/дренаж;
- continuous moisture field;
- altitude/temperature coupling;
- slope/exposure;
- richer substrate/resource field;
- seasonal variation;
- spatial disturbance history;
- сравнительные runs на нескольких seeds.

VIS2 отвечает на вопрос: возникают ли визуально разные устойчивые сообщества **из причин среды и истории**, а не из нарисованной карты биомов.

## ECO.XFER-VIS

После VIS1/VIS2 лабораторный provider заменяется на world provider:

```text
LabTerrain + LabEnvironmentProvider
              ↓ replace
Planet/World Surface + WorldEnvironmentProvider
```

Начальный production-scale target — один настоящий surface region примерно `1 x 1 km`, а не вся планета.

Переносятся:

- EnvironmentSample contract;
- ecology-to-presentation projection;
- numeric diagnostics;
- overlays;
- experiment/replay tools, где они уместны для developer mode.

Не переносится как production truth:

- лабораторная ручная карта;
- отдельная lab persistence/authority;
- hard-coded biome labels;
- presentation geometry как ecology truth.

## Ownership boundary

VIS1/VIS2 — research/presentation work.

Они не владеют:

- global persistence durability;
- server authority/cross-server handoff;
- World Query;
- lifecycle/work-budget foundations;
- terrain/geology truth;
- material ontology;
- network replication policy.

Поэтому этот визуальный track может развиваться отдельно от CRITICAL P4.4/P4.5 production convergence, пока не меняет эти foundations.

## Immediate implementation order

```text
VIS1.0  Lab scene + terrain + camera/operator movement
VIS1.1  EcoEnvironmentProvider + LabEnvironmentProvider
VIS1.2  existing ecology snapshot -> spatial lab projection
VIS1.3  PH5 renderer materialization on the polygon
VIS1.4  time controls + same-seed restart
VIS1.5  numerical dashboard + time-series capture
VIS1.6  diagnostic overlays
VIS1.7  disturbance painting/actions + event log
VIS1.8  0->200 year comparative experiment + acceptance
VIS2    causal landscape expansion
XFER-VIS replace lab provider with real simulator surface provider
```

Главный критерий ближайшего этапа: не количество новых ecology features, а возможность глазами и числами ответить на вопрос **«что именно эта экология делает с ландшафтом во времени и почему?»**.
