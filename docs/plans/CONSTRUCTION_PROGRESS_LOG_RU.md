# Журнал движения строительной линии

Этот файл является хронологическим журналом. Архитектурная карта находится в `CONSTRUCTION_MAP_RU.md`, подробный план — в `CONSTRUCTION_ROADMAP_RU.md`.

## 2026-07-31 — C0: архитектурная парадигма

**Статус:** ACCEPTED как направление линии.

Зафиксировано:

- стройка нового уровня вместо отдельного block editor;
- четыре опоры: semantic scale, composite items, facet compilation, capability-based behavior;
- граница Item Graph / ConstructAggregate;
- контрольные объекты: стол, робот, дом, сборщик, корабельная секция;
- необходимость авторитетной сетевой командной границы.

## 2026-07-31 — C1: Semantic Construction Kernel

**Статус:** ACCEPTED, delivery fix1.

База:

```text
main @ 2879fdb7134032f645ffc5c98c0535aecfc09caf
feature/c1-semantic-construction-kernel
```

Реализовано:

- `ConstructionPartRecord`;
- `ConstructionBondRecord`;
- `ConstructSnapshot`;
- `ConstructAggregate`;
- revision/replay fencing;
- capability compiler;
- стол как первый vertical slice;
- обязательное включение C1 в world regression.

Приёмка:

```text
Focused C1:       PASS — 66 assertions
Network N0–M4:    PASS
World regression: PASS — 101/101 tests, 104 steps
```

## 2026-07-31 — C2A: Item Graph Contracts

**Статус:** IMPLEMENTED CANDIDATE, ожидает внешней приёмки.

Архитектурное решение:

- C2 разделён на C2A и C2B;
- C2A остаётся полностью изолированным от runtime;
- установленная деталь использует существующую семантику `ATTACHMENT`;
- `assembly_id = construct_id`;
- `parent_item_id = construct root item`;
- `socket_id = part_id`;
- резервирование существует только в transaction plan до commit;
- C2A plan проектируется как будущий builder для M0 `MutationBatch`.

Реализовано:

- item projection, совместимая с `planet_simulator.item_instance.v2`;
- item mutation contracts;
- construct mutation contract;
- checksum-protected transaction plan;
- transaction planner сборки и разборки;
- adapter port;
- in-memory atomic adapter;
- exact replay, operation conflict, stale preconditions;
- retryable injected failure без частичного commit;
- JSON round-trip и persistent replay;
- сборка стола из пяти item-backed деталей;
- расход четырёх крепежей из stack 8;
- разборка с возвратом деталей и сохранением расхода крепежа.

Локальная проверка реализации:

```text
C2A contracts:    PASS — 46 assertions
C2A transactions: PASS — 91 assertions
Focused total:    PASS — 2/2 tests, 137 assertions
```

Полный regression должен быть повторно запущен на рабочем checkout перед присвоением `ACCEPTED`.

## Следующее движение

После приёмки C2A строительная линия остаётся изолированной до multiplayer gate. Разрешённые параллельные задачи:

- уточнение mapping C2A plan → M0 MutationBatch;
- проектирование C3 BuildPlan без runtime-подключения;
- подготовка контрактов CompositeDefinition;
- расширение тестовых сложных случаев.

Реальный Item Graph изменяется только на C2B.

## 2026-07-31 — C2A: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c2a-item-graph-contracts`
**Коммит:** `68cf8b2 feat(construction): add C2A Item Graph contracts`

```text
C1 compatibility:  PASS — 66 assertions
Focused C2A:       PASS — 137 assertions
Network N0–M4:     PASS
World regression:  PASS — 103/103 tests, 106 steps
```

C2A сохранён как изолированный контрактный слой и стал базой C2B.

## 2026-07-31 — C2B: Authoritative Item Graph Integration

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c2b-authoritative-item-graph-integration`
**База:** принятый C2A `68cf8b2`.

Реализовано:

- production adapter к `ItemRegistry`, `ContainerRegistry`, `ItemRelationshipValidator`, `ItemMassService`;
- общий `ItemOperationLedger` вместо отдельного construction ledger;
- `ConstructStore` для item-backed constructs;
- детерминированный перевод C2A plan в M0 `MutationBatch`;
- три авторитетных aggregate family: Item Graph, ledger, Construct;
- M0 adapter и transaction bridge;
- атомарная сборка и разборка стола;
- exact replay, operation conflict, terminal rejection и retryable failure;
- rollback локальной materialization после частичного применения;
- crash recovery после M0 commit;
- раздельные revisions внутреннего construct и M0 envelope;
- checksum-protected persistence и restart replay;
- отказ от загрузки persisted state, расходящегося с M0 authority.

Локальный focused-профиль реализации:

```text
C2B contracts:     PASS — 64 assertions
C2B integration:   PASS — 194 assertions
Focused C2B:       PASS — 258 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
```

Внешняя приёмка должна дополнительно подтвердить network regression и world regression с 105 тестами.

## 2026-07-31 — C2B: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c2b-authoritative-item-graph-integration`.
**База:** `feature/c2a-item-graph-contracts @ 68cf8b2`.
**Commit:** ещё не создан на момент начала C3.

Подтверждено пользователем:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C2B:             PASS — 258 assertions
Network/runtime: PASS
World regression: PASS
Main-scene CLI:  PASS — 6/6
Static checks:   PASS
```

Проверенная поставка C2B:

```text
31 files
SHA-256: 960D14B3D120EFF2BCBAD04BD15FA161E759C07348548E67E147C65B52B7787E
```

C2B принят как единственная authorititative граница реального расхода материалов, attach/detach и изменения ConstructAggregate.

## 2026-07-31 — C3: BuildPlan and Ghost Construction

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c3-build-plan-and-ghost`.
**База:** принятый C2B в `feature/c2b-authoritative-item-graph-integration`.

Архитектурные решения:

- BuildPlan является immutable execution-plan конкретной стройки;
- reusable blueprint/definition separation отложена до C4;
- BuildPlan хранит exact source item projections и exact material allocations;
- каждая стадия детерминированно восстанавливает одинаковый C2A transaction checksum;
- ghost не входит в Item Graph и не имеет массы/capabilities;
- после первой стадии физическим является partial construct, а ghost остаётся projection прогресса;
- progress ghost является recoverable projection и не сильнее C2B construct/ledger;
- partial stage snapshots принудительно не публикуют operational capabilities;
- stage execution всегда проходит через C2B-compatible `apply_plan()`;
- crash после authoritative stage commit восстанавливается через construct checksum и shared operation result;
- divergence между BuildPlan и authoritative construct отклоняется явно.

Реализовано:

- `ConstructionBuildStage`;
- `ConstructionBuildPlan`;
- `ConstructionGhostState`;
- `ConstructionBuildPlanStore`;
- `ConstructionStageSnapshotBuilder`;
- `ConstructionStageTransactionPlanner`;
- `ConstructionBuildProcess`;
- `ConstructionBuildPlanPersistence`;
- минимальный `ConstructionBuilderAgent`;
- новая C2A command `ADVANCE_CONSTRUCTION_STAGE`;
- operation-result lookup в C2A sandbox adapter и C2B production adapter;
- трёхстадийный стол: FOUNDATION → FRAME → COMMISSIONING;
- exact replay, capability gate, crash reconciliation, persistence и divergence guard.

Локальный focused-профиль реализации:

```text
C3 contracts:    PASS — 80 assertions
C3 integration:  PASS — 106 assertions
Focused C3:      PASS — 2/2, 186 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
```

Полный C2B/network/world regression должен быть повторно запущен на основном checkout перед присвоением C3 статуса `ACCEPTED`.

## 2026-07-31 — C3 review fix1: canonical preconditions

**Статус:** BLOCKER FIXED LOCALLY, EXTERNAL RECHECK REQUIRED.
**Ветка:** `feature/c3-build-plan-and-ghost`.
**Base полного checkout:** `C2B @ d5c9187`.

Внешняя проверка первоначального C3 остановила focused integration на FRAME: сохранённый FOUNDATION snapshot и новый raw before-snapshot были семантически равны, но отличались числовыми Variant-типами после canonicalization. Прямое сравнение словарей выдавало `CONSTRUCT_PRECONDITION_MISMATCH`.

Fix1:

- raw Dictionary equality заменено на `UtilsScript.canonical_json(...)` для construct preconditions;
- такое же исправление применено к item preconditions;
- добавлен regression, принудительно меняющий `state_revision` и item `revision` между `int` и `float`;
- C3 integration увеличен с 106 до 114 assertions.

Локальная повторная проверка:

```text
C1:            PASS — 66 assertions
C2A:           PASS — 137 assertions
C3 contracts:  PASS — 80 assertions
C3 integration: PASS — 114 assertions
C3 total:      PASS — 194 assertions
Editor parse:  PASS
```

C2B, network/runtime, world regression и main-scene CLI остаются обязательными для внешней приёмки fix1.


## 2026-07-31 — C3 fix1: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c3-build-plan-and-ghost`.
**База:** `C2B @ d5c9187`.

```text
C1:               PASS — 66 assertions
C2A:              PASS — 137 assertions
C2B:              PASS — 258 assertions
C3 contracts:     PASS — 80 assertions
C3 integration:   PASS — 114 assertions
C3 total:         PASS — 194 assertions
Network N0–M4:    PASS
World regression: PASS — 107/107 tests, 110 steps
```

Reviewed delivery: 42 files, SHA-256 `2296f48f0f31c8d4feb9290e0973d27dd4b4f85ed9c7f29361f28156b82ac256`. C3 стал базой C4.

## 2026-07-31 — C4: CompositeDefinition

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c4-composite-definition`.
**База:** принятый C3 fix1.

Архитектурные решения:

- definition хранит semantic slots, topology и requirements, но не concrete instance IDs;
- завершённый C3 construct можно повысить в reusable definition;
- новый экземпляр создаётся deterministic late binding реальных item projections;
- concrete binding сохраняется в отдельном immutable instantiation record;
- definition versioning последовательное и replay-safe;
- C4 компилирует обычный C3 BuildPlan и не меняет authoritative execution path;
- partial/final constructs сохраняют pinned definition provenance;
- typed parameters валидируются, нормализуются и pin-ятся в instantiation;
- exposed ports связываются semantic slot → concrete part и появляются только после установки части;
- material bindings обязаны точно совпадать с allocations конкретного BuildPlan;
- cosmetic/incompatible parts и недостаточные materials fail closed.

Локальный focused-профиль:

```text
C4 contracts:      PASS — 112 assertions
C4 integration:    PASS — 152 assertions
Focused C4 total:  PASS — 264 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
C3 compatibility: PASS — 194 assertions
Editor parse:      PASS
```

Полный C2B/network/world/main-scene профиль должен быть повторён на полном checkout перед присвоением C4 статуса `ACCEPTED`.


## 2026-07-31 — C4 fix1: canonical provenance comparison

**Статус:** BLOCKER FIXED LOCALLY, EXTERNAL RECHECK REQUIRED.
**Ветка:** `feature/c4-composite-definition`.
**Base полного checkout:** `C3 @ 4917f55`.

Внешний focused C4 подтвердил contracts `112 assertions`, но integration завершился с 5 ошибками. Причина была не в потере provenance: C2A in-memory adapter канонизировал JSON DTO и мог преобразовать целочисленные `float` в `int`. Тесты сравнивали `composite_parameters` и `composite_exposed_ports` raw-оператором `==`, поэтому семантически одинаковые данные считались различными.

Fix1:

- parameters и exposed ports сравниваются через `NetworkContractUtils.canonical_json`;
- contract comparison параметров приведён к той же семантике;
- добавлен regression для `100.0 ↔ 100` и `0.0 ↔ 0`;
- production schema и execution path C4 не изменялись.

Локальная повторная проверка:

```text
C1:             PASS — 66 assertions
C2A:            PASS — 137 assertions
C3:             PASS — 194 assertions
C4 contracts:   PASS — 112 assertions
C4 integration: PASS — 156 assertions
C4 total:       PASS — 268 assertions
Editor parse:   PASS
```

C2B, network/runtime, полный world regression и main-scene CLI остаются обязательными для внешней приёмки C4 fix1.


## 2026-07-31 — C4 fix1: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c4-composite-definition`.

```text
C4 contracts:     PASS — 112 assertions
C4 integration:   PASS — 156 assertions
C4 total:         PASS — 268 assertions
C1/C2A/C2B/C3:    PASS
Network N0–M4:    PASS
World regression: PASS — 109/109 tests, 112 steps
git diff --check: PASS
```

C4 fix1 SHA-256: `d6c03e2a9b2b34c879f45a392741ccddc01cf35fb5822ff8ec1e986bd0a0cb67`. C4 стал принятой базой C5.

## 2026-07-31 — C5: Capability and Affordance Compilation

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c5-capability-affordance-compilation`.
**База:** принятый C4 fix1.

Архитектурные решения:

- authoritative source остаётся `ConstructSnapshot`;
- behavior profile является checksum-pinned rebuildable projection;
- capability описывает semantic ability и concrete provider parts/ports;
- affordance описывает concrete action, target, actor requirements и properties;
- partial/damaged constructs публикуют пустой behavior profile;
- C4 parameters (`load_rating_kg`, `finish`) становятся query constraints;
- agent/resolver не зависят от prefab/display name;
- одинаковые queries сортируются priority → construct ID → affordance ID;
- stale и same-revision conflicts fail closed;
- persisted cache загружается транзакционно и может быть полностью rebuilt.

Реализовано:

- `ConstructionCapabilityDescriptor`;
- `ConstructionAffordanceDescriptor`;
- `ConstructionBehaviorProfile`;
- `ConstructionBehaviorCompiler`;
- `ConstructionBehaviorProfileStore`;
- `ConstructionBehaviorPersistence`;
- `ConstructionAffordanceQuery`;
- `ConstructionAffordanceResolver`;
- `ConstructionAffordanceAgent`;
- support/container/seat/climb/workstation/mounting vertical behaviors;
- C4 staged table integration и damage invalidation.

Локальный focused/compatibility профиль:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5 contracts:    PASS — 105 assertions
C5 integration:  PASS — 99 assertions
C5 total:        PASS — 204 assertions
Editor parse:    PASS
```

Полный C2B/network/world/main-scene профиль должен быть выполнен на полном checkout. Ожидаемый world profile: `111/111 tests`, `114 steps`.


## 2026-07-31 — C5 fix1: strict-schema negative-test

**Статус:** BLOCKER FIXED LOCALLY, EXTERNAL RECHECK REQUIRED.
**Ветка:** `feature/c5-capability-affordance-compilation`.

Внешняя focused-проверка C5 остановилась на одном contracts-тесте: fixture добавлял поле через property syntax, поэтому ключ получал невалидный для JSON DTO тип и contract закономерно возвращал `INVALID_FIELD_NAME`. Тест должен был проверять другую ветку — корректный строковый неизвестный ключ и ответ `UNEXPECTED_FIELD`.

Fix1:

- negative-test использует `unexpected["unexpected_field"] = true`;
- ожидание остаётся `UNEXPECTED_FIELD`;
- production behavior contracts и compiler не изменены.

Локальный профиль после fix1:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5 contracts:    PASS — 105 assertions
C5 integration:  PASS — 99 assertions
C5 total:        PASS — 204 assertions
Editor parse:    PASS
```

Полный C2B/network/world/main-scene профиль требуется повторить на полном checkout.

## 2026-07-31 — C5 fix1: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c5-capability-affordance-compilation`.
**База:** `C4 @ b985cde`.

```text
C1:               PASS — 66 assertions
C2A:              PASS — 137 assertions
C2B:              PASS — 258 assertions
C3:               PASS — 194 assertions
C4:               PASS — 268 assertions
C5 contracts:     PASS — 105 assertions
C5 integration:   PASS — 99 assertions
Network N0–M4:    PASS
World regression: PASS — 111/111 tests, 114 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

C5 стал принятой базой C6. Fix1 изменил только strict-schema negative-test и вошёл в общую C5-поставку.

## 2026-07-31 — C6: Mobile Construct

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c6-mobile-construct`.
**База:** принятый C5 fix1.

Архитектурные решения:

- authoritative source остаётся `ConstructSnapshot`;
- subsystem definitions связывают semantic subsystem с concrete parts и bonds;
- provider quorum поддерживает redundant components;
- health выводится из part condition, bond state и dependency graph;
- `DAMAGED` mobile construct может сохранять часть capabilities;
- C5 capability/affordance descriptors переиспользуются без второго behavior vocabulary;
- mobile command pin-ит profile checksum и actor requirements;
- store отклоняет stale/same-revision mutation;
- persistence/rebuild не создают новый authoritative state;
- physics movement, network endpoint и UI не входят в C6.

Локальный focused/compatibility профиль:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5:              PASS — 204 assertions
C6 contracts:    PASS — 92 assertions
C6 integration:  PASS — 126 assertions
C6 total:        PASS — 218 assertions
Editor parse:    PASS
```

C2B focused не запускается в isolated construction workspace из-за отсутствующей production M0 dependency tree. Network/runtime, полный world regression и main-scene CLI обязательны для внешней приёмки. Ожидаемый world profile: `113/113 tests`, `116 steps`.


## 2026-07-31 — C6: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c6-mobile-construct`.
**База:** `C5 @ 29cd8b1`.

```text
C6 contracts:     PASS — 92 assertions
C6 integration:   PASS — 126 assertions
C6 total:         PASS — 218 assertions
C1/C2A/C2B/C3/C4/C5: PASS
Network N0–M4:    PASS
World regression: PASS — 113/113 tests, 116 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

Reviewed SHA-256: `b24ce4ee4efc891ca8ed4621e8e9a40fb80b82e486e6f98c6b450b1447867c04`. C6 стал принятой базой C7.

## 2026-07-31 — C7: Spatial Construct

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c7-spatial-construct`.
**База:** принятый C6.

Архитектурные решения:

- `ConstructSnapshot` остаётся authoritative source;
- Space Graph хранится semantic DTO, а не извлекается из mesh;
- sections вычисляют health из concrete parts, bonds и quorum;
- openings связывают spaces с exterior и closure part;
- enclosure и habitability вычисляются отдельно от utility availability;
- utility graph поддерживает dependencies и cascade;
- building state и activation LOD полностью derived;
- C5 descriptors переиспользуются для spatial capabilities/affordances;
- spatial command pin-ит profile checksum;
- navigation, geometry activation, door animation и network endpoint не входят в C7.

Локальный focused/compatibility профиль:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5:              PASS — 204 assertions
C6:              PASS — 218 assertions
C7 contracts:    PASS — 105 assertions
C7 integration:  PASS — 120 assertions
C7 total:        PASS — 225 assertions
Editor parse:    PASS
```

C2B focused не запускается в isolated workspace из-за отсутствующей M0 dependency tree. Network/runtime, полный world regression и main-scene CLI обязательны для внешней приёмки. Ожидаемый world profile: `115/115 tests`, `118 steps`.


## 2026-07-31 — C7: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c7-spatial-construct`.
**База:** `C6 @ 2837835`.

```text
C7 contracts:     PASS — 105 assertions
C7 integration:   PASS — 120 assertions
C7 total:         PASS — 225 assertions
C1/C2A/C2B/C3/C4/C5/C6: PASS
Network N0–M4:    PASS
World regression: PASS — 115/115 tests, 118 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

Reviewed SHA-256: `5a4cebb21587ed8c4b54852145b6a018445438866bc1908d5cf9bcc4fe9aee87`. C7 стал принятой базой C8.


## 2026-07-31 — C8: Fabrication Cell

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c8-fabrication-cell`.
**База:** принятый C7.

Архитектурные решения:

- recipes публикуются как immutable versioned DTO;
- machine profile выводится из `ConstructSnapshot`, C5 behavior и C7 utilities;
- job pin-ит recipe/machine checksum и точные item bindings;
- C2A расширен командами reserve/complete/release и fabrication item purposes;
- C2B authoritative adapter остаётся единственным production mutation path;
- work progress идемпотентен по operation ID;
- completion атомарно расходует input, создаёт output и обновляет machine snapshot;
- cancel возвращает зарезервированные входы;
- crash reconcile использует authoritative machine runtime и exact replay;
- fabricated outputs возвращаются в обычный Item Graph и C3 BuildPlan;
- integral float/int components сравниваются канонически.

Локальный focused/compatibility профиль:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5:              PASS — 204 assertions
C6:              PASS — 218 assertions
C7:              PASS — 225 assertions
C8 contracts:    PASS — 91 assertions
C8 integration:  PASS — 130 assertions
C8 total:        PASS — 221 assertions
Editor parse:    PASS
```

C2B focused не запускается в isolated workspace из-за отсутствующей M0 dependency tree. Network/runtime, полный world regression и main-scene CLI обязательны для внешней приёмки. Ожидаемый world profile: `117/117 tests`, `120 steps`.


## 2026-07-31 — C8: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c8-fabrication-cell`.
**База:** `C7 @ 923bfe1`.

```text
C8 contracts:     PASS — 91 assertions
C8 integration:   PASS — 130 assertions
C8 total:         PASS — 221 assertions
C1–C7 + C2B:      PASS
Network N0–M4:    PASS
World regression: PASS — 117/117 tests, 120 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

Reviewed SHA-256: `977056921d0da4fe148a9496524b90908afe1aafcd3b2d95f7b1fbe1681f477e`. C8 стал принятой базой C9.


## 2026-07-31 — C9: Damage, Split, Repair

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c9-damage-split-repair`.
**База:** принятый C8.

Архитектурные решения:

- damage pin-ит source checksum и explicit retained part;
- topology split считается через connected components;
- крупные components становятся child constructs, мелкие — salvage;
- source/children/items изменяются одной multi-aggregate transaction;
- C2A item mutations расширены damage/split/salvage/repair purposes;
- C2B adapter и M0 translator получили общий multi-construct path;
- repair plan хранит original snapshot и реальные required item IDs;
- process replay восстанавливает outcome из authoritative damage metadata;
- repair ghost показывает missing/available parts;
- history store и persistence поддерживают replay/conflict/transactional load.

Локальный focused/compatibility профиль:

```text
C1:              PASS — 66 assertions
C2A:             PASS — 137 assertions
C3:              PASS — 194 assertions
C4:              PASS — 268 assertions
C5:              PASS — 204 assertions
C6:              PASS — 218 assertions
C7:              PASS — 225 assertions
C8:              PASS — 221 assertions
C9 contracts:    PASS — 96 assertions
C9 integration:  PASS — 108 assertions
C9 total:        PASS — 204 assertions
Editor parse:    PASS
```

C2B focused не запускается в isolated workspace из-за отсутствующей полной M0 dependency tree. Production adapter/translator parse PASS, multi-aggregate batch покрыт contract test. Ожидаемый world profile: `119/119 tests`, `122 steps`.


## 2026-07-31 — C9: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c9-damage-split-repair`.
**База:** `C8 @ 6ec6fdb`.

```text
C9 contracts:     PASS — 96 assertions
C9 integration:   PASS — 108 assertions
C9 total:         PASS — 204 assertions
C1–C8 + C2B:      PASS
Network N0–M4:    PASS
World regression: PASS — 119/119 tests, 122 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

Reviewed SHA-256: `1db35602564d6a3f77cbd7b49770839e36c7705c7e6ef40f33c073f20e4582fb`. C9 стал принятой базой C10.


## 2026-07-31 — C10: Parametric Members

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c10-parametric-members`.
**База:** принятый C9.

Архитектурные решения:

- material/definition DTO versioned и checksum-pinned;
- member instance вычисляет geometry, mass и stock usage;
- beam/panel/pipe/cable/layered wall используют один compiler boundary;
- fabricated output остаётся обычным Item Graph projection;
- C3 BuildPlan использует тот же item ID;
- C5 capabilities компилируются из member kind;
- C9 split/repair сохраняет parametric component;
- local segmentation консервативна по mass/volume/materials;
- catalog/member store persistence transactional;
- renderer geometry не является authoritative.

Локальный профиль:

```text
C1:               PASS — 66 assertions
C2A:              PASS — 137 assertions
C3:               PASS — 194 assertions
C4:               PASS — 268 assertions
C5:               PASS — 204 assertions
C6:               PASS — 218 assertions
C7:               PASS — 225 assertions
C8:               PASS — 221 assertions
C9:               PASS — 204 assertions
C10 contracts:    PASS — 155 assertions
C10 integration:  PASS — 84 assertions
C10 total:        PASS — 239 assertions
Editor parse:     PASS
```

Полный C2B/network/world/main-scene profile остаётся внешним gate. Ожидаемый world profile: `121/121 tests`, `124 steps`.


## 2026-08-01 — C10: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c10-parametric-members`.
**База:** `C9 @ 8d8bf77`.

```text
C10 contracts:     PASS — 155 assertions
C10 integration:   PASS — 84 assertions
C10 total:         PASS — 239 assertions
C2B regression:    PASS — 258 assertions
Network N0–M4:     PASS
World regression:  PASS — 121/121 tests, 124 steps
git diff --check:  PASS
Manifest:          50/50 unique
```

Reviewed SHA-256: `062dea4395947c4bb969fe4628621e1d07208c01eb935912a958a98c5cbddf9c`. C10 стал принятой базой C11.


## 2026-08-01 — C11: Local Geometry Editing

**Статус:** ACCEPTED.
**Коммит:** `6d26f69`.
**Рекомендуемая ветка:** `feature/c11-local-geometry-editing`.
**База:** принятый C10.

Архитектурные решения:

- edit request pin-ит member, item и construct preconditions;
- parameter/control-point operations являются strict checksum DTO;
- constraints хранятся в authoritative geometry state;
- path length передаётся в C10 compiler для mass/material recomputation;
- ItemProjection, PartRecord и ConstructSnapshot обновляются одной transaction;
- relation и item/member/definition identities неизменны;
- audit record сохраняется в construct facets и history store;
- exact replay/crash recovery не повторяют authoritative commit;
- C5 capabilities и C8 recipes перестраиваются из нового member checksum;
- renderer/collision остаются derived.

Focused профиль:

```text
C11 contracts:     PASS — 109 assertions
C11 integration:   PASS — 90 assertions
C11 total:         PASS — 199 assertions
Editor parse:      PASS
```

Ожидаемый внешний world profile: `123/123 tests`, `126 steps`.


## 2026-08-01 — C12: Multiplayer Construction Acceptance

**Статус:** ACCEPTED.
**Reviewed SHA-256:** `85c455c72dc1d5651f86672dc3d20e851e3c650bfa575c5643883f1da78c7f29`.
**Рекомендуемая ветка:** `feature/c12-multiplayer-construction-acceptance`.
**База:** C11 delivery поверх принятого C10; C11 ещё требует внешней приёмки.

Архитектурные решения:

- permissions являются checksum-pinned grants с монотонным epoch;
- reconnect создаёт новый session epoch и сохраняет next command sequence;
- commands pin-ят construct checksum и optional server generation;
- C12 routes в существующие C3/C9/C11 processes и не создаёт второй mutation path;
- successful commands публикуют contiguous events с canonical state bundle;
- exact command replay не создаёт второй event;
- gateway crash после domain commit восстанавливается через terminal operation ledger;
- replicas отклоняют event gaps, rollback и tamper;
- reconnect возвращает missing event range и доказывает checksum convergence;
- gateway/session/permission state сохраняется транзакционно.

Focused профиль:

```text
C12 contracts:    PASS — 53 assertions
C12 integration:  PASS — 71 assertions
C12 total:        PASS — 124 assertions
```

Ожидаемый внешний world profile: `125/125 tests`, `128 steps`.


## 2026-08-01 — C13: Runtime Geometry and Physics Projection

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c13-runtime-geometry-physics-projection`.
**База:** принятый C12 поверх C11 `6d26f69`.

Архитектурные решения:

- runtime request и descriptors остаются strict JSON DTO;
- C10/C11 geometry компилируется в Box/Cylinder/path segments;
- scene projection создаёт реальные MeshInstance3D и CollisionShape3D;
- static/mobile body выбирается по C6 profile, immobile body замораживается;
- C7 opening status обновляет door transform и collision;
- runtime opening создаёт NavigationLink3D и interaction anchor;
- unchanged part node сохраняется при incremental rebuild;
- C9 split переносит item-backed part между runtime construct roots;
- descriptor store поддерживает stale/same-revision rejection и persistence;
- очистка всей presentation сцены и rebuild дают тот же world checksum;
- ни один Godot Object не записывается в Item Graph/ConstructSnapshot.

Focused профиль:

```text
C13 contracts:    PASS — 58 assertions
C13 integration:  PASS — 66 assertions
C13 total:        PASS — 124 assertions
Editor parse:     PASS
```

Локально повторно пройдены C1–C8, C10–C12. C9/C2B/network/full world/main-scene остаются внешним gate из-за отсутствия полного production M0/item-domain дерева в изолированном workspace. Ожидаемый world profile: `127/127 tests`, `130 steps`.


## 2026-08-01 — C13: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c13-runtime-geometry-physics-projection`.
**База:** C12 `1152c94`.
**Reviewed SHA-256:** `7b08bfc5972cde3a3bf1435b6d27564caeb5111bf8aa6edbd75c0c24e08f6b73`.

```text
C13 focused:      PASS
C2B regression:   PASS — 258 assertions
Network N0–M4:    PASS
World regression: PASS — 127/127 tests, 130 steps
Manifest:         36/36
```

C13 стал принятой базой C14.


## 2026-08-01 — C14: Structural Integrity and Load Paths

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c14-structural-integrity-load-paths`.

Реализованы strict load cases, support/load-path compiler, part/bond utilization, safety/degraded/buckling limits, progressive collapse, C9 damage/split/repair integration, exact replay/conflict detection, profile store, persistence и dormant summary.

```text
C14 contracts:    PASS — 90 assertions
C14 integration:  PASS — 78 assertions
C14 total:        PASS — 168 assertions
```

Ожидаемый внешний world profile: `129/129 tests`, `132 steps`.


## 2026-08-01 — C14: внешняя приёмка

**Статус:** ACCEPTED.

```text
C14 focused:      PASS — 168 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
Network N0–M4:    PASS
World regression: PASS — 129/129 tests, 132 steps
Main-scene CLI:   PASS — 6/6
```

C14 стал принятой базой C15.

## 2026-08-01 — C15: Executable Utilities and Machines

**Статус:** IMPLEMENTED CANDIDATE.
**Рекомендуемая ветка:** `feature/c15-executable-utilities-machines`.

Реализованы generic utility networks для POWER/WATER/AIR/HEAT/DATA, deterministic priority allocation, losses, storage charge/discharge, atomic load shedding, execution profile store/persistence и checksum-pinned utility lease для C8 fabrication.

```text
C15 contracts:    PASS — 92 assertions
C15 integration:  PASS — 123 assertions
C15 total:        PASS — 215 assertions
```

Локально повторно пройдены C1–C8 и C10–C14. Ожидаемый внешний world profile: `131/131 tests`, `134 steps`.


## 2026-08-01 — C15: внешняя приёмка

**Статус:** ACCEPTED.

```text
C15 focused:      PASS — 215 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
Network N0–M4:    PASS
World regression: PASS — 131/131 tests, 134 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

C15 стал принятой базой C16.

## 2026-08-01 — C16: Construction Interaction and Editing UX

**Статус:** IMPLEMENTED CANDIDATE.
**База:** принятый C15.
**Рекомендуемая ветка:** `feature/c16-construction-interaction-editing-ux`.

Реализованы semantic snap targets/resolver, checksum-pinned placement solutions, headless placement ghost, C11 control-point gizmo, build/repair material overlays, graphical status panel и C12-only command adapter. UI не получает прямой ссылки на authoritative construction processes.

```text
C16 contracts:    PASS — 39 assertions
C16 integration:  PASS — 32 assertions
C16 total:        PASS — 71 assertions
Expected world:   133/133 tests, 136 steps
```


## 2026-08-01 — C16: внешняя приёмка

**Статус:** ACCEPTED.
**Ветка:** `feature/c16-construction-interaction-editing-ux`.
**Коммит:** `a4376cd`.

```text
C16 focused:      PASS — 71 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
Network N0–M4:    PASS
World regression: PASS — 133/133 tests, 136 steps
Main-scene CLI:   PASS — 6/6
```

C16 стал принятой базой C17.

## 2026-08-01 — C17: Distributed Construction Authority

**Статус:** IMPLEMENTED CANDIDATE.
**База:** C16 `a4376cd`.
**Рекомендуемая ветка:** `feature/c17-distributed-construction-authority`.

Реализованы single-writer authority records, owner routing, authority epoch, migration fence/handoff, terminal-operation transfer, cross-epoch replay, read-only replicas/sections, cross-zone split child, item-transfer authorization, owner-failure takeover и persistence.

```text
C17 contracts:    PASS — 59 assertions
C17 integration:  PASS — 66 assertions
C17 total:        PASS — 125 assertions
Local C1–C17:     PASS — 2798 assertions excluding C2B/C9
Expected world:   135/135 tests, 138 steps
```


## 2026-08-01 — C18: Streaming, LOD and Dormant Constructs

**Статус:** IMPLEMENTED CANDIDATE поверх C17 focused candidate.
**Рекомендуемая ветка:** `feature/c18-streaming-lod-dormant-constructs`.

Реализованы activity levels, interest/hysteresis, три budget-класса, LOD contracts, C13 lazy rebuild, owner-only bounded catch-up, dormant preservation pending jobs/operations и persistence без SceneTree.

```text
C18 contracts:    PASS — 51 assertions
C18 integration:  PASS — 84 assertions
C18 total:        PASS — 135 assertions
Local C1–C8/C10–C18: 2933 assertions, PASS
Expected world:   137/137 tests, 140 steps
```


## 2026-08-02 — C17/C18: внешняя приёмка

**Статус:** ACCEPTED.

```text
C18 focused:      PASS — 135 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17 regression:   PASS — 125 assertions
Network N0–M4:    PASS
World regression: PASS — 137/137 tests, 140 steps
Main-scene CLI:   PASS — 6/6
```

C18 стал принятой базой C19.

## 2026-08-02 — C19: Agent Construction and Automation API

**Статус:** IMPLEMENTED CANDIDATE.
**База:** принятый C18.
**Рекомендуемая ветка:** `feature/c19-agent-construction-automation-api`.

Реализованы build/repair/salvage goals, deterministic BOM, C8 fabrication fallback, atomic resource reservations, persisted work queue, C12/C17 command execution и restart replay.

```text
C19 contracts:    PASS — 97 assertions
C19 integration:  PASS — 57 assertions
C19 total:        PASS — 154 assertions
Local C1–C8/C10–C19: PASS — 3087 assertions
Expected world:   139/139 tests, 142 steps
```

## 2026-08-02 — C19: внешняя приёмка

**Статус:** ACCEPTED.

```text
C19 focused:      PASS — 154 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17 regression:   PASS — 125 assertions
C18 regression:   PASS — 135 assertions
Network N0–M4:    PASS
World regression: PASS — 139/139 tests, 142 steps
Main-scene CLI:   PASS — 6/6
```

## 2026-08-02 — C20: Logistics and Construction Economy

**Статус:** IMPLEMENTED CANDIDATE.
**База:** принятый C19.
**Рекомендуемая ветка:** `feature/c20-logistics-construction-economy`.

Реализованы procurement, landed-cost planning, atomic escrow/stock reservation, warehouses, multi-leg delivery, contractors, salvage market, C8 multi-cell production chains и persistence/replay.

```text
C20 contracts:    PASS — 38 assertions
C20 integration:  PASS — 76 assertions
C20 total:        PASS — 114 assertions
Expected world:   141/141 tests, 144 steps
```


## 2026-08-02 — C20: внешняя приёмка

**Статус:** ACCEPTED.

```text
C20 focused:      PASS — 114 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17–C19:          PASS
Network N0–M4:    PASS
World regression: PASS — 141/141 tests, 144 steps
Main-scene CLI:   PASS — 6/6
```

C20 стал принятой базой C21.

## 2026-08-02 — C21: Large-Scale Construction Acceptance

**Статус:** IMPLEMENTED CANDIDATE.
**База:** принятый C20.
**Рекомендуемая ветка:** `feature/c21-large-scale-construction-acceptance`.

Добавлен масштабный acceptance harness для 20–30 тысяч constructs, 1–2 тысяч BuildPlan, массовых C8/C19/C20 flows, C17 migrations/reconnect storms, C18 budgets и persistence/restart.

```text
C21 contracts:    PASS — 26 assertions
C21 integration:  PASS — 52 assertions
C21 soak:         PASS — 26 assertions
C21 total:        PASS — 104 assertions
Expected world:   144/144 tests, 147 steps
```


## 2026-08-02 — C21: внешняя приёмка

**Решение:** ACCEPTED.

```text
C21 focused:      PASS — 104 assertions
C2B regression:   PASS — 258 assertions
C9 regression:    PASS — 204 assertions
C17–C20:          PASS
Network N0–M4:    PASS
World/Main gate:  PASS
git diff --check: PASS
Manifest:         39/39
```

C21 стал принятой базой C22.

## 2026-08-02 — C22: Compiled Construct Proxies and Hierarchical Detail Streaming

**База:** принятый C21.
**Статус:** IMPLEMENTED CANDIDATE.

Добавлена иерархия shell/section/interior proxies для крупных item-backed constructs. Реальный fixture содержит 10 000 частей, но дальний packet содержит один shell artifact и не раскрывает дочерние item identities.

```text
C22 contracts:    PASS — 29 assertions
C22 integration:  PASS — 52 assertions
C22 graphical:    PASS — 35 assertions
C22 scale/soak:   PASS — 75 assertions
C22 total:        PASS — 191 assertions
```

Проверены 80 stable sections, 56 600 удалённых внутренних граней, greedy meshing, 83 content-addressed artifacts, bounded section/interior streaming, C13 exact descriptors только для interactive parts, incremental damage rebuild, persistence/restart и read-only distributed compilation.

Ожидаемый внешний gate: C2B 258, C9 204, C17–C21, Network N0–M4, world 148/148 тестов и 151 шаг.
