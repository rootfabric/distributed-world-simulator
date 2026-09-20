# EVO ARCH2 — Roadmap R2

Статус: CURRENT ROADMAP UPDATE. Дата: 2026-09-20.

Источник исходного train: `docs/research/ecology/EVO_ARCH2_A0_RECONCILIATION_RU.md` из принятой research-линии A0–A7.

Эта редакция не переписывает исторические accepted документы и не изменяет frozen product A10. Она фиксирует актуальное продолжение после A10 и добавляет отдельный этап **A10.5 / ECO-POLYGON-1** между A10 и A11.

## 1. Цель всей линии

Цель ECO ARCH2 — **EVOLVABLE LIVING WORLD**: наследуемые программы развития создают тела, тела взаимодействуют со средой, среда меняется от организмов, ресурсы ограничивают рост/выживание/размножение, а новые поколения наследуют и изменяют генетическую программу.

Полигон A10.5 нужен не как отдельная модель и не как декоративная лаборатория. Это **малый совместимый фрагмент будущего симулятора**, предназначенный для управляемых опытов, визуальной проверки и исследования уже реализованных возможностей A1–A10.

Наработки полигона должны переноситься в основной симулятор без переписывания biological/world truth.

## 2. Актуальный train

| Этап | Результат / назначение |
|---|---|
| A0 | Scope/evidence/owner reconciliation |
| A1 | Versioned genome/program/body/state/phenotype |
| A2 | Persistent development, growth points, bounded paid operations |
| A3 | Parameter/regulatory/structural mutation; real rule editing / Morphology Lab |
| A4 | Local conservative environment fields and organism ports |
| A5 | Resource-funded survival, maintenance, growth and reproduction |
| A6 | Persistent niche construction, death, decomposition, mineralization and abiotic update |
| A7 | Three-location Observatory; wet/dry/dark, common-garden and controlled experiments |
| A8 | Full organism+field snapshot, restart, persistence and seam ownership |
| A9 | Ecological fidelity separated from render LOD; FULL/REDUCED/PATCH/AGGREGATE |
| A10 | Selective integration with current world: terrain/Matter/Construction/damage/Region/handoff |
| **A10.5 / ECO-POLYGON-1** | **Simulator-compatible experimental workbench: edit, seed, place, run, observe, save, fork, replay and compare ecology experiments using the real A1–A10 model** |
| A11 | Visible persistent evolving habitat acceptance |

## 3. A10.5 / ECO-POLYGON-1 — назначение

A10.5 создаёт сильный пользовательский инструмент для опытов над живой системой.

Он должен позволять собрать небольшой habitat, выбрать или изменить организмы, рассадить их в разных условиях, запустить симуляцию, наблюдать развитие во времени, сохранить состояние, вернуться к нему, сделать альтернативную ветку эксперимента и сравнить результаты.

Это не mock и не отдельный simplified ecology runtime. Полигон обязан использовать те же canonical данные и переходы, которые затем используются основным симулятором.

Базовая архитектурная формула:

```text
real Genome / DevelopmentProgram
        ↓
real BodyGraph / DevelopmentState
        ↓
real PhenotypeSnapshot
        ↓
real A4 environment + A5/A6 lifecycle
        ↓
A8 persistence / replay
        ↓
A9 fidelity / visualization controls
        ↓
A10 world-compatible bindings where applicable
        ↓
ECO-POLYGON-1 UI / experiment orchestration only
```

UI полигона не становится новым biological owner, resource owner, Region owner или persistence owner.

### 3.1 Свободная эволюция — обязательный canonical invariant

ECO не должен превращаться в выбор одной из заранее заданных форм. Каноническая причинная цепочка остаётся:

```text
Genome
  ↓
DevelopmentProgram
  ↓
structural / regulatory / parameter expression
  ↓
BodyGraph
  ↓
physiology + mechanics + behaviour
  ↓
environment interaction / fitness
  ↓
reproduction + mutation
```

Обязательные правила:

- Genome не обязан содержать `species_type`, `TREE`, `BUSH`, `QUADRUPED`, `BIRD`, `FISH` или другой визуальный archetype;
- structural mutation может создавать новую топологию BodyGraph, если она проходит canonical biological/physical validation;
- неизвестная ранее морфология не может быть отброшена только потому, что для неё нет curated asset;
- visual/archetype layer не может переписывать Genome, DevelopmentProgram или canonical BodyGraph;
- morphotype/archetype допускается как **derived classification результата**, но не как обязательная причина формы;
- curated organization должен быть явным экспериментальным входом, а не скрытым default;
- режим `FREE` отключает организационные bias'ы, но **не отключает** conservation, resource costs, world physics, ownership и другие реальные законы среды.

Таким образом A10.5 исследует открытое пространство морфологий, а не комбинаторику заранее изготовленных существ.

### 3.2 Morphology Realizer: NMS-подобные идеи только после BodyGraph

Полезные идеи modular procedural art переносятся только в слой реализации фенотипа:

```text
canonical BodyGraph
        ↓
MorphologyDescriptor
        ↓
Generic Realizer ──────────────┐
        │                       │
        └→ Specialized Realizer│
                                ↓
                     mesh / skeleton / skin
                     materials / animation
```

`MorphologyDescriptor` является derived view над canonical BodyGraph и не становится вторым морфологическим truth.

**Generic Realizer обязателен.** Он должен уметь представить ранее неизвестную валидную структуру через универсальные примитивы/процедуры (segments, tubes, capsules, junctions, membranes, surfaces или их будущие эквиваленты). Specialized/curated realization может улучшать качество распространённых форм, но отсутствие подходящего набора не является причиной отклонения организма.

Это создаёт важную страховку:

```text
new evolved topology
        ↓
curated realization exists?
   YES ─────→ high-quality realization
    NO ─────→ generic procedural realization
```

Renderer и presentation assets не влияют на fitness или ecological state, если отдельное функциональное свойство не объявлено в canonical biological model.

### 3.3 OrganizationProfile — опциональное давление на пространство форм

Для управляемых экспериментов вводится **не новый тип организма**, а versioned `OrganizationProfile` / organization rule set.

Минимальные исследовательские presets:

- `FREE` — без дополнительных организационных bias'ов;
- `SOFT` — слабые вероятностные bias'ы к повторяемости, симметрии и согласованным структурам;
- `EARTH_LIKE` — исследовательский набор явных developmental bias'ов к знакомым земным морфологическим мотивам;
- `NMS_LIKE` — исследовательский preset модульной визуально согласованной организации, вдохновлённый общим procedural-art подходом; без зависимости от внешнего кода/assets;
- `CUSTOM` — явно заданный набор правил и весов.

Профиль не может скрыто превращаться в обязательную grammar. Предпочтительная модель — **soft bias**, например:

```text
paired_appendage_bias = 0.80
bilateral_symmetry_bias = 0.70
segment_repeat_bias = 0.55
visual_coherence_bias = 0.90
```

а не:

```text
allowed_body = QUADRUPED
allowed_heads = [A, B, C]
allowed_legs = [A, B]
```

Каждый bias должен быть:
- явно назван;
- versioned;
- сохранён в experiment manifest;
- детерминирован при одинаковом seed;
- независимо отключаем;
- различим в provenance и сравнительном отчёте.

### 3.4 Три класса правил нельзя смешивать

Организация разделяется на три уровня:

1. **VISUAL_ONLY** — palette/material/mesh smoothing/skin/joint presentation. Не меняет canonical BodyGraph, ecological hash, fitness или reproduction.
2. **DEVELOPMENT_BIAS** — меняет вероятности/веса разрешённых developmental или mutation transitions и поэтому является явным входом эксперимента.
3. **BIOLOGICAL/WORLD CONSTRAINT** — реальные resource, mechanics, physiology, conservation и world-law ограничения. Они принадлежат canonical model/world contracts и не могут незаметно появляться из visual profile.

Если исследователь хочет превратить визуальную эвристику в реальное биологическое правило, это отдельная versioned rule/model change с собственным validation/provenance, а не переключение renderer preset.

### 3.5 Emergent morphotypes, а не предзаданные виды

После прогонов система может анализировать результаты и находить устойчивые морфологические кластеры:

```text
evolved BodyGraphs
        ↓
derived morphology features
        ↓
clustering / similarity
        ↓
emergent morphotype labels
```

Например можно получить оценки `bilateral_like`, `radial_like`, `branched_like`, `segmented_like` или автоматически найденный cluster id. Эти labels являются аналитикой. По умолчанию они не участвуют в развитии следующего поколения.

Если некоторый emergent cluster становится частым, для него можно позже добавить Specialized Realizer, не меняя уже существующие Genome/BodyGraph и сохраняя Generic Realizer как fallback.

## 4. Обязательные возможности

### 4.1 Experiment setup

Пользователь должен иметь возможность создать новый опыт и задать:

- deterministic seed;
- длительность опыта / число ticks / поколений в доступной модели;
- один или несколько участков/зон среды;
- начальное число организмов;
- выбранные genomes / blueprints / lineages;
- стартовые ресурсы и environmental conditions;
- включённые mutation operators и их разрешённые параметры;
- `OrganizationProfile` и явные веса organization/development bias'ов; default для проверки свободного пространства — `FREE`;
- режимы feedback / decomposition / mineralization;
- скорость отображения и симуляции;
- набор метрик и сохраняемых checkpoints.

Все настройки должны быть сохранены как versioned experiment manifest, чтобы опыт можно было повторить точно.

### 4.2 Genome / organism editor

Полигон должен позволять исследовать генетическую систему без редактирования исходного кода:

- открыть canonical genome/program;
- видеть genes, rules и module parameters;
- менять разрешённые parameter/regulatory/structural значения;
- включать/выключать mutation operators;
- создавать вариант от существующего genome;
- сравнивать parent/variant;
- показывать validation errors до запуска;
- сохранять варианты в библиотеку эксперимента;
- видеть structural topology/BodyGraph без обязательного сведения к заранее заданному archetype;
- отдельно видеть derived morphotype classification и выбранный OrganizationProfile, не смешивая их с genotype.

Редактор не должен разрешать произвольный executable code в genotype и не должен обходить A1/A3 validation. Он также не должен требовать curated archetype для сохранения или запуска валидного genome.

### 4.3 Placement / рассадка

Пользователь должен иметь возможность разместить организмы или группы организмов в разных условиях:

- вручную по участкам;
- по сетке/зонам;
- случайно от фиксированного seed;
- одинаковые founders в разных environments;
- разные founders в одинаковой среде;
- mixed population;
- controlled/common-garden layout.

Размещение должно использовать canonical spatial/environment addressing, а не отдельную UI-only систему координат.

### 4.4 Environment editor

Для research-сценария должны редактироваться только явно разрешённые входы среды, например:

- water;
- nutrient / organic stocks;
- light;
- temperature;
- mechanical/environment signals;
- пространственная неоднородность;
- bounded disturbances.

Единицы, bounds, conservation и ownership должны оставаться такими же, как в A4/A10 contracts.

### 4.5 Run controls

Минимальный набор управления:

- RUN / PAUSE;
- single tick / bounded step;
- ускоренные режимы;
- run-to-condition / run-to-horizon;
- RESET к исходному experiment manifest;
- checkpoint;
- restore;
- deterministic replay.

Ускорение не должно менять ecological tick semantics или генерировать другой biological result только из-за UI frame rate.

### 4.6 Save / restore / fork / replay

Полигон обязан использовать A8-compatible state:

- сохранить полный experiment checkpoint;
- восстановить его;
- создать fork от любого сохранённого checkpoint;
- изменить условия после fork;
- повторить исходную ветку;
- сравнить две ветки;
- доказать одинаковый result при одинаковом source+seed+inputs.

История опыта должна различать:
- immutable source/checkpoint;
- дальнейшую ветку A;
- дальнейшую ветку B;
- operator annotations.

Сохранение полигона не должно вводить второй формат истины вместо A8.

### 4.7 Visual observation

Полигон должен стать основным визуальным окном во все сделанные ECO-возможности:

- видимый BodyGraph / phenotype;
- рост во времени;
- организмы живые/мертвые;
- offspring и lineage;
- ресурсы среды;
- corpse/decomposition;
- damage/effective function;
- spatial distribution;
- population counts;
- morphology/genotype diversity;
- births/deaths;
- resource balances;
- mutation events;
- generic vs specialized morphology realization;
- derived/emergent morphotype similarity без записи labels обратно в genotype;
- активный OrganizationProfile и его фактические bias weights;
- owner/region/seam state при world-compatible режиме.

Пользователь должен иметь возможность выбрать организм и увидеть:
`genome → development → body → function → resources → lineage`.

### 4.8 Variants and comparison

Полигон должен поддерживать не только один красивый прогон, но и реальные сравнительные эксперименты:

```text
Variant A  vs  Variant B  vs  Variant C
same seed / different environment
same environment / different genome
mutation ON / OFF
feedback ON / OFF
FREE vs SOFT vs NMS_LIKE organization
same genome + visual-only profile A/B
different founder sets
multiple deterministic seeds
```

Нужен batch runner для bounded серии запусков и сравнительный отчёт по заранее выбранным метрикам.

Результаты отдельных seeds нельзя скрыто выбирать по принципу "удачной картинки".

## 5. Совместимость с основным симулятором

Это главный invariant A10.5.

**ECO-POLYGON-1 = simulator slice, not parallel simulator.**

Разрешено:
- отдельная Godot scene;
- experiment UI;
- editors;
- orchestration;
- visualization;
- research presets;
- batch execution;
- reports.

Запрещено:
- второй Genome truth;
- второй BodyGraph;
- отдельные polygon-only lifecycle rules;
- отдельная формула reproduction/survival;
- бесплатные polygon resources;
- UI-owned mutation semantics;
- отдельный save format, который нельзя связать с A8;
- guessed Matter meaning;
- обязательный visual archetype как условие валидности Genome/BodyGraph;
- renderer write-back в canonical Genome/DevelopmentProgram/BodyGraph;
- скрытый organization bias, отсутствующий в experiment manifest/provenance;
- отказ от валидной новой морфологии только из-за отсутствия curated asset;
- bypass Region/owner rules в world-compatible mode.

Любой компонент, который предполагается переносить в основной симулятор, должен зависеть от shared contracts/runtime, а не от scene-specific state.

Хороший результат A10.5 должен позволить переносить в основной simulator:
- experiment/world presets;
- genome variants;
- visualization widgets;
- organism inspector;
- placement tools;
- time controls;
- checkpoint/replay UI;
- metrics;
- comparison tools;
- habitat scene components,

без переноса альтернативной biological logic.

## 6. Два режима полигона

### LAB mode

Изолированная bounded research среда для быстрых опытов.

Использует настоящие A1–A9 biological contracts/runtime, но может работать с явно synthetic/local environment fixtures. Это основной режим для исследования генов, морфологии, feedback и evolutionary scenarios.

### WORLD-COMPAT mode

Использует A10 bindings к реальным World/Matter/Region/Construction/Handoff contracts.

Нужен для проверки, что эксперимент, подготовленный в LAB, может быть перенесён в настоящий simulator habitat без смены biological semantics.

LAB и WORLD-COMPAT могут отличаться источником world/environment data, но не правилами организма.

OrganizationProfile ортогонален этому выбору: `FREE`, `SOFT`, `NMS_LIKE` или custom experiment может запускаться как LAB-исследование, а допустимый совместимый набор — позднее проверяться через WORLD-COMPAT. Сам режим WORLD-COMPAT не имеет права скрыто включать curated morphology.

## 7. Минимальный пользовательский сценарий acceptance

A10.5 нельзя считать готовым только по unit tests. Должен проходить видимый end-to-end опыт:

1. Создать новый experiment.
2. Выбрать два canonical founder genomes.
3. Запустить базовую ветку с `OrganizationProfile=FREE` и подтвердить отсутствие обязательного curated archetype.
4. Создать от одного founder изменённый разрешённый gene/rule/structural variant.
5. Создать минимум три environmental zones, например WET / DRY / DARK или custom.
6. Рассадить одинаковые и разные founders по зонам.
7. Запустить simulation.
8. Наблюдать реальные growth/resource/lifecycle/mutation events и валидную ранее неизвестную BodyGraph topology через Generic Realizer.
9. Сохранить checkpoint.
10. Продолжить исходный вариант.
11. Вернуться к checkpoint и создать альтернативный fork с другим условием.
12. От того же source+seed сделать отдельный fork с `SOFT` или `NMS_LIKE` organization и сохранить профиль как причинное различие эксперимента.
13. Переиграть исходную FREE-ветку и получить deterministic повтор.
14. Сравнить branches по population, morphology, resources, births/deaths, lineage и morphology-cluster metrics.
15. Экспортировать experiment manifest + organization profile + checkpoints + report.
16. Загрузить совместимый scenario/state через simulator-compatible route без переопределения biological truth.

## 8. Acceptance gates

A10.5 считается завершённым только если:

- polygon использует real A1–A10 contracts, а не дубликаты;
- genome editor проходит canonical validation;
- placement/environment edits детерминированы и versioned;
- одинаковый experiment manifest + seed даёт одинаковый результат;
- save → restore продолжает ту же историю;
- save → fork создаёт отдельную явно связанную историю;
- replay исходной ветки совпадает;
- visualization не меняет simulation state;
- `VISUAL_ONLY` profile не меняет canonical ecology/BodyGraph hash;
- `FREE` работает без обязательных TREE/QUADRUPED/other archetype labels;
- валидная неизвестная BodyGraph topology имеет Generic Realizer fallback;
- Specialized Realizer не является условием biological validity;
- `DEVELOPMENT_BIAS` явно входит в manifest/provenance и детерминирован при одинаковом seed;
- изменение organization profile не маскируется как изменение genome/environment;
- derived morphotype labels по умолчанию не пишутся обратно в genotype и не влияют на reproduction;
- batch comparison сохраняет все seeds и не выбирает winner скрыто;
- resource/material balances не ломаются;
- WORLD-COMPAT mode не обходит owner/epoch/Region/Matter rules;
- экспортированный эксперимент пригоден как вход/настройка для дальнейшего simulator integration;
- fresh independent review/verifier подтверждают отсутствие polygon-only biological truth.

## 9. Что A10.5 сознательно не обязано закрывать

A10.5 — инструмент и simulator-compatible slice, а не финальная экосистема мира.

Он не обязан сам по себе доказывать:

- бесконечную эволюцию;
- production-scale million-organism simulation;
- окончательную species model;
- полный набор curated morphotype/archetype assets;
- сведение всего пространства эволюции к ограниченному каталогу форм;
- глобальную калибровку биологии;
- весь planet generation;
- полную gameplay ecology;
- production authority promotion.

Эти вопросы продолжаются после полигона.

## 10. Переход к A11

A10.5 даёт инструменты, которыми A11 должен пользоваться, а не переписывать их.

```text
A10
production-compatible bindings
        ↓
A10.5 / ECO-POLYGON-1
experiment + visualization + replay workbench
        ↓
A11
visible persistent evolving habitat
```

A11 должен брать проверенные через полигон genomes, habitat presets, placement, Generic/Specialized Realizer, OrganizationProfile controls, visualization, checkpoint/replay и experiment tooling и переносить их в persistent living-world scenario.

При этом `FREE` остаётся обязательным supported mode A11: curated/NMS-like organization может улучшать читаемость и художественную согласованность мира, но не становится единственным способом существования или отображения организмов.

Таким образом A10.5 становится одновременно:
1. исследовательской лабораторией;
2. визуальным окном во все возможности ECO;
3. regression/debugging workbench;
4. инструментом подбора и сравнения evolutionary scenarios;
5. малым совместимым фрагментом основного симулятора.
