# Checkpoint C4 — CompositeDefinition

**Дата:** 2026-07-31
**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C3 fix1 поверх `C2B @ d5c9187`
**Рекомендуемая ветка:** `feature/c4-composite-definition`

## Цель

Отделить повторно используемый семантический тип конструкции от конкретного item-backed экземпляра и при этом сохранить единственный authoritative execution path C3 → C2A → C2B.

## Реализованная цепочка

```text
completed C3 operational construct
+ immutable accepted BuildPlan
        ↓ promotion
CompositeDefinition v1
        ↓ deterministic late binding
CompositeInstantiation v1
+ concrete C3 BuildPlan
        ↓
ConstructionBuildProcess
        ↓
C2A transaction plan
        ↓
C2B Item Graph / ledger / M0 authority
```

## Контракты

- `planet_simulator.composite_part_slot.v1`;
- `planet_simulator.composite_bond_template.v1`;
- `planet_simulator.composite_stage_template.v1`;
- `planet_simulator.composite_parameter_definition.v1`;
- `planet_simulator.composite_exposed_port.v1`;
- `planet_simulator.construction_composite_definition.v1`;
- `planet_simulator.construction_composite_instantiation.v1`;
- `planet_simulator.construction_composite_registry.v1`.

## Definition/instance separation

`CompositeDefinition` хранит:

- semantic part slots;
- требуемый `definition_id` детали;
- optional subset required components;
- part kind, role, mass и локальную позицию;
- bond templates между slots;
- stage templates;
- material requirements по definition и quantity;
- required capabilities;
- typed parameters с default values;
- exposed semantic ports, привязанные к part slots;
- version, provenance и checksum.

Definition намеренно не содержит:

- item instance IDs;
- root item ID;
- construct ID;
- BuildPlan ID;
- operation/transaction plan ID;
- container identity.

Concrete binding хранится в отдельном `CompositeInstantiation`, который pin-ит definition ID/version/checksum, BuildPlan checksum, полный нормализованный набор parameter values и mappings slot → item → part.

## Promotion

`ConstructionCompositeDefinitionExtractor` принимает только завершённый operational snapshot, который соответствует финальной стадии валидного C3 BuildPlan. Он заменяет instance part/bond/stage IDs semantic templates и агрегирует stage consumptions в material requirements.

Partial или divergent construct не может быть опубликован как reusable definition.

## Compilation

`ConstructionCompositeBuildPlanCompiler`:

1. проверяет definition;
2. канонизирует набор доступных item projections;
3. детерминированно выбирает детали по item ID;
4. проверяет required component subset;
5. создаёт уникальные part/bond/stage IDs нового экземпляра;
6. поздно распределяет consumables между реальными stacks;
7. разрешает typed parameter overrides и заполняет defaults;
8. связывает exposed ports semantic slot → concrete part ID;
9. создаёт target `ConstructSnapshot` с pinned definition provenance;
10. выпускает обычный C3 BuildPlan;
11. создаёт checksum-защищённый instantiation record.

Одинаковые IDs и одинаковое множество источников дают одинаковые checksums независимо от порядка входного массива.

Material bindings проверяются не только по итоговым quantities, но и как точное соответствие stage allocations конкретного C3 BuildPlan. Registry дополнительно проверяет parameter set/type относительно зарегистрированной definition и не принимает произвольное увеличение generation.

## Versioning и persistence

Registry поддерживает:

- exact registration replay;
- immutable version;
- строго последовательные версии `1, 2, ...`;
- pinned retrieval старой версии;
- несколько concrete instantiations одной definition;
- conflict по instantiation/build-plan/construct identity;
- checksum-protected JSON persistence;
- transactional rejection повреждённого состояния.

Публикация v2 не переписывает существующие v1 instances.

## Vertical slice

Завершённый C3-стол повышается в:

```text
composite-definition/furniture/reusable-table@1
```

Из него создаются два независимых стола:

```text
instance first  → собственные items/root/construct/BuildPlan
instance second → другой набор items/root/construct/BuildPlan
```

У ножек есть component requirement:

```text
grade.class = structural
```

Поэтому cosmetic beam отклоняется. Четыре крепежа детерминированно распределяются между двумя stacks, каждый stack сохраняет минимум одну единицу. Оба экземпляра проходят FOUNDATION → FRAME → COMMISSIONING через C3 builder-agent.

Partial и final snapshots сохраняют:

```text
composite_definition_id
composite_definition_version
composite_definition_checksum
composite_instantiation_id
composite_parameters
composite_exposed_ports
```

Порт публикуется в partial snapshot только после установки связанной детали. В контрольном сценарии `port/work-surface` доступен после FOUNDATION, а `port/service-anchor`, связанный с четвёртой ножкой, появляется только после FRAME.

## Локальная проверка

```text
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
C3 compatibility: PASS — 194 assertions
C4 contracts:     PASS — 112 assertions
C4 integration:   PASS — 152 assertions
Focused C4:       PASS — 264 assertions
Editor parse:     PASS
```

Focused tests выполнялись на `Godot 4.7.1.stable.double.custom_build.a13da4feb` в изолированном construction workspace.

Статические проверки: manifest 42/42, world-runner 109/109 уникальных тестов, ожидаемые 112 шагов, JSON/shell/UTF-8/LF/UID/git diff checks PASS, unsafe archive paths 0, byte-exact overlay replay 42/42.

## Ограничения C4 v1

- part resolver использует exact `definition_id` и component subset, но ещё не tags/substitution scores;
- C4 уже типизирует и pin-ит parameter values, но процедурное изменение геометрии параметрами относится к C10/C11;
- material stack пока нельзя израсходовать полностью из-за C2A v1 UPDATE-only consumption;
- exposed ports пока являются semantic provenance/facet data; runtime connection routing относится к C5–C8;
- registry ещё не опубликован через gameplay/network API;
- UI каталога, naming и permissions не входят в C4;
- full C2B/network/world/main-scene проверки требуют полный checkout.

## Acceptance gate

```text
RUN_C1_CONSTRUCTION_KERNEL_TESTS.ps1
RUN_C2A_CONSTRUCTION_ITEM_GRAPH_TESTS.ps1
RUN_C2B_AUTHORITATIVE_ITEM_GRAPH_TESTS.ps1
RUN_C3_BUILD_PLAN_TESTS.ps1
RUN_C4_COMPOSITE_DEFINITION_TESTS.ps1
RUN_NETWORK_CONTRACT_TESTS.ps1
RUN_WORLD_REGRESSION_TESTS.ps1
main-scene CLI

git diff --check
```

После внешнего PASS C4 становится базой C5 — capability/affordance layer для использования неизвестных пользовательских constructs агентами и gameplay systems.


## C4 fix1 — каноническое сравнение provenance DTO

Внешняя проверка исходного кандидата C4 остановила focused integration: `CompositeDefinition` и compiled provenance переносились корректно, но тесты сравнивали raw Godot `Dictionary`/`Array`. После JSON canonicalization адаптер мог представить целочисленный `float` как `int` (`100.0 → 100`, `0.0 → 0`), поэтому raw equality ошибочно сообщала потерю параметров и exposed ports.

Fix1 в той же ветке `feature/c4-composite-definition`:

- проверки `composite_parameters` переведены на `NetworkContractUtils.canonical_json(...)`;
- проверки `composite_exposed_ports` переведены на тот же semantic comparison;
- contract-проверка provenance также использует canonical JSON;
- добавлен regression, где raw DTO с `100.0/100` и координатами `0.0/0` различаются как Variant-контейнеры, но обязаны совпасть канонически.

Локальная повторная проверка fix1:

```text
C4 contracts:    PASS — 112 assertions
C4 integration:  PASS — 156 assertions
Focused C4:      PASS — 268 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
C3 compatibility: PASS — 194 assertions
Editor parse:    PASS
```

Статус: **BLOCKER FIXED LOCALLY, EXTERNAL RECHECK REQUIRED**. Полный C2B/network/world/main-scene профиль должен быть повторён на полном checkout до присвоения C4 статуса `ACCEPTED`.
