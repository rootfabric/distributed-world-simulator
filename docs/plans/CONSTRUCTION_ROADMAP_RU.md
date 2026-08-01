# Дорожная карта строительной линии PlanetSimulator

## Стратегическая цель

PlanetSimulator создаёт **конструктор нового уровня**, основанный на сочетании:

- семантического масштаба;
- составных item-backed предметов;
- компиляции независимых facets;
- capability-based поведения;
- авторитетных сетевых транзакций;
- локальной активации сложности.

Это не вспомогательная система размещения блоков. Строительная модель должна стать общей парадигмой объектов мира: от стола и робота до дома, корабля и города.

Наглядная актуальная карта: `docs/plans/CONSTRUCTION_MAP_RU.md`.
Хронология решений: `docs/plans/CONSTRUCTION_PROGRESS_LOG_RU.md`.
Подробная карта C13–C22: `docs/plans/CONSTRUCTION_POST_C12_ROADMAP_RU.md`.

## Стратегия интеграции

Строительный трек развивается последовательно поверх принятых доменных границ:

```text
C1 semantic construct
→ C2A transaction contracts
→ C2B production Item Graph + M0 authority
→ C3 resumable BuildPlan
→ C4 reusable CompositeDefinition
```

Ни один последующий этап не получает права обходить C2B. Любая реальная установка детали или расход материала выполняются через его authoritative transaction path.

## C0 — архитектурная фиксация

- парадигма стройки нового уровня;
- границы Item Graph/ConstructAggregate;
- отдельные structural, kinematic, flow, space и capability graphs;
- facets и activity levels;
- сценарии стола, робота, дома, сборщика и корабельной секции.

**Статус:** ACCEPTED.

## C1 — Semantic Construction Kernel

- строгие `PartRecord`, `BondRecord`, `ConstructSnapshot`;
- item-backed root identity;
- revision/replay fence;
- deterministic snapshot/checksum;
- capability compiler;
- стол как первый vertical slice.

**Статус:** ACCEPTED, fix1.

## C2A — Item Graph Contracts

- совместимая проекция `item_instance.v2`;
- canonical `ATTACHMENT` для установленной детали;
- item/construct mutations;
- checksum-protected transaction plan;
- exact before-state preconditions;
- атомарный in-memory adapter;
- exact replay, conflict, retryable failure и rollback;
- сборка и разборка стола.

**Статус:** ACCEPTED, commit `68cf8b2`.

## C2B — Authoritative Item Graph Integration

- реальные `ItemRegistry`, `ContainerRegistry`, relationship validator и mass service;
- общий `ItemOperationLedger`;
- deterministic C2A plan → M0 `MutationBatch`;
- M0 prepare/commit как authority;
- crash recovery из M0;
- atomic local materialization и rollback;
- persistence без права откатить M0;
- независимые internal construct revision и M0 aggregate revision.

**Статус:** ACCEPTED после полного локального regression; commit ещё должен быть создан в ветке C2B.

## C3 — BuildPlan and Ghost Construction

### Цель

Перевести стройку из мгновенной операции в resumable процесс:

```text
проект
→ невесомый ghost
→ проверка деталей, материалов и инструментов
→ стадия
→ частичный construct
→ следующая стадия
→ commissioning
→ operational construct
```

### Реализованный scope C3

#### Immutable BuildPlan

`ConstructionBuildPlan` содержит:

- build plan ID;
- construct/root identity;
- ghost world relation;
- полный target `ConstructSnapshot`;
- точные исходные item projections;
- упорядоченные stages;
- exact material allocations;
- required capabilities;
- checksum.

C3 BuildPlan является execution-plan конкретной стройки. Переиспользуемая definition/blueprint separation появляется в C4.

#### BuildStage

Каждая стадия содержит:

- sequence index;
- semantic state;
- cumulative included parts;
- cumulative included bonds;
- material allocations;
- required tool/actor capabilities.

Стадии монотонны: уже включённые parts/bonds не исчезают. Финальная стадия обязана включить полный target и перейти в `OPERATIONAL`.

#### GhostState

До первой стадии ghost:

- не входит в Item Graph;
- не имеет массы;
- не имеет capabilities;
- не создаёт collision или physics object;
- не создаёт root item;
- является intention/progress projection.

После начала стройки ghost не заменяет частичный construct, а показывает оставшийся план.

#### StageSnapshot compiler

Из cumulative stage content компилируется deterministic `ConstructSnapshot`:

- внутренний revision равен stage index;
- промежуточные состояния используют `PARTIAL`;
- final stage использует `OPERATIONAL`;
- partial capabilities принудительно пусты;
- final capabilities вычисляются тем же C1 compiler.

#### Stage transaction planner

Каждая стадия переводится в обычный C2A transaction plan с новой командой:

```text
ADVANCE_CONSTRUCTION_STAGE
```

Первая стадия:

```text
CREATE root item
ATTACH first parts
CONSUME stage materials
CREATE partial construct
```

Последующие стадии:

```text
ATTACH newly included parts
CONSUME stage materials
UPDATE construct snapshot
```

BuildPlan хранит исходные projections и cumulative allocations, поэтому before/after projections и checksum стадии детерминированы даже после restart.

#### BuildProcess

`ConstructionBuildProcess`:

- регистрирует BuildPlan;
- сверяет ghost с authoritative construct;
- проверяет expected stage index;
- проверяет required capabilities;
- строит deterministic C2A plan;
- исполняет его через C2B-compatible adapter;
- обновляет ghost только после authoritative success;
- поддерживает exact replay;
- восстанавливает progress после crash между C2B commit и ghost update;
- отклоняет divergence.

#### Builder agent

Минимальный `ConstructionBuilderAgent` исполняет следующий stage или весь BuildPlan через тот же `ConstructionBuildProcess`. Он не является отдельным способом строительства и не меняет Item Graph напрямую.

#### Persistence

`ConstructionBuildPlanStore` хранит immutable plans и recoverable ghost projections с checksum. Ошибочная загрузка не мутирует активное состояние.

### Контрольный vertical slice C3

Трёхстадийный стол:

1. `FOUNDATION`: столешница, две ножки, два крепежа;
2. `FRAME`: ещё две ножки, два крепежа;
3. `COMMISSIONING`: герметик и inspection capability.

Проверяются:

- ghost без массы и capabilities;
- PARTIAL snapshots;
- отсутствие operational capabilities до final stage;
- exact replay;
- capability gate;
- расход материалов ровно один раз;
- crash после authoritative commit;
- reconciliation;
- divergence rejection;
- persistence;
- builder agent.

### Acceptance C3

- C1 и C2A compatibility profiles проходят;
- C2B focused profile проходит на полном checkout;
- оба C3 теста проходят;
- C3 тесты включены в world regression;
- network/runtime regression проходит;
- world regression и main-scene CLI проходят;
- partial construct не имеет capabilities;
- ghost не имеет Item identity, массы и capabilities;
- crash recovery не расходует материал повторно;
- changed operation ID не может повторно завершить stage;
- divergent construct не маскируется ghost progress;
- `git diff --check` проходит.

**Статус:** ACCEPTED вместе с fix1.

## C4 — CompositeDefinition

### Цель

Сохранить завершённую пользовательскую конструкцию как повторно используемый **семантический тип**, не превращая её в жёсткий prefab и не теряя реальный состав каждого экземпляра.

### Реализованный scope C4

- promotion завершённого operational construct + C3 BuildPlan в `CompositeDefinition`;
- part slots вместо конкретных item IDs;
- bond templates, ссылающиеся на slots;
- stage templates и material requirements по `definition_id`;
- optional required component subset для выбора совместимых деталей;
- immutable checksum и provenance source construct/build plan;
- последовательное versioning в registry;
- typed parameter definitions, defaults и pinned instance values;
- exposed ports, привязанные к semantic part slots;
- deterministic late binding реальных Item projections;
- распределение расходников между несколькими stacks без полного исчерпания;
- компиляция обычного C3 BuildPlan;
- отдельный `CompositeInstantiation` с pinned definition version/checksum, parameter values и concrete bindings;
- registry/persistence definitions и instantiations;
- перенос definition provenance, parameters и доступных ports в partial и operational ConstructSnapshot;
- два независимых экземпляра стола из одного определения;
- execution, replay и crash reconciliation через неизменённый C3/C2A/C2B путь.

### Инварианты C4

1. Reusable definition не содержит `item/`, `construct/`, `build-plan/`, `operation/` или transaction plan identity.
2. Definition topology выражается через semantic slots, а не instance records.
3. Concrete binding детерминирован при одинаковом наборе источников независимо от порядка входного массива.
4. Один item не связывается с двумя part slots.
5. Material requirements разрешаются поздно и фиксируются в instantiation record как точное отражение stage allocations.
6. Parameter set/type определяются definition, а полный нормализованный набор значений pin-ится в instantiation.
7. Exposed port разрешается slot → concrete part и публикуется только когда part присутствует в stage snapshot.
8. Definition version immutable; изменение требует следующей последовательной версии.
9. Existing instantiation остаётся pinned на исходную version/checksum после публикации новой версии.
10. Скомпилированный план является обычным C3 BuildPlan и не получает альтернативного execution path.
11. Partial construct сохраняет definition provenance, но не operational capabilities.
12. Реальный расход и attach по-прежнему проходят только через C2B authority boundary.

### Контрольный vertical slice C4

Завершённый C3-стол повышается до `composite-definition/furniture/reusable-table`. Из определения компилируются два новых стола с разными item IDs, root IDs, construct IDs и parameter values. Для ножек требуется structural component grade; cosmetic beam детерминированно отклоняется. Четыре крепежа распределяются между двумя stacks, typed parameters pin-ятся в instances, exposed ports связываются с конкретными деталями, затем оба BuildPlan выполняются builder agents через C3.

**Статус:** ACCEPTED вместе с fix1.

## C5 — Capability and Affordance Compilation

C5 компилирует authoritative `ConstructSnapshot` в rebuildable `ConstructionBehaviorProfile`.

Поддерживаются:

- support surface и place-item;
- container access: open/store/take;
- seat;
- climbable;
- workstation;
- mounting surface;
- actor capability requirements;
- property constraints по C4 parameters;
- deterministic query ordering;
- invalidation при PARTIAL/DAMAGED;
- persistence и rebuild из authoritative snapshot.

Критические инварианты:

1. Profile pin-ит construct checksum/revision и не может менять authoritative state.
2. Affordance ссылается только на provider part/port собственного capability.
3. Partial и damaged objects имеют ноль operational affordances.
4. Same revision с другим source checksum отклоняется.
5. Stale profile не заменяет более новую проекцию.
6. Resolver не использует prefab, scene или display name.
7. Actor получает действие только при полном наборе requirements.
8. Одинаковые profile/query inputs дают одинаковый ordered result.
9. C4 numeric properties сравниваются канонически.
10. Потерянный profile store полностью перестраивается из snapshots.

Контрольный vertical slice: C4 table проходит три стадии; до commissioning действий нет. После commissioning generic agent находит concrete work-surface port. Среди двух неизвестных tables выбирается painted instance с нагрузкой не менее 120 кг. После break bond action исчезает.

**Статус:** ACCEPTED вместе с fix1.

## C6 — Mobile Construct

C6 вводит rebuildable mobile profile поверх authoritative `ConstructSnapshot`. Мобильность больше не является одним флагом объекта: она выводится из конкретных подсистем, provider quorum, bonds и dependency graph.

Поддерживаются subsystem kinds:

- `POWER`;
- `CONTROL`;
- `DRIVE`;
- `SENSOR`;
- `COMMUNICATION` как контракт для последующего remote-link vertical slice.

Каждая subsystem definition содержит concrete provider parts, обязательные bonds, зависимости, minimum online providers и свойства. Compiler формирует `ONLINE`, `DEGRADED` или `OFFLINE` state и затем переиспользует C5 capability/affordance descriptors.

### Инварианты C6

1. Authoritative source — только `ConstructSnapshot`; mobile profile является cache/projection.
2. Subsystem не может ссылаться на отсутствующую part, bond или dependency.
3. Dependency graph не содержит циклов.
4. Provider partition полон и не пересекается.
5. Quorum ниже minimum переводит subsystem в `OFFLINE`.
6. `DEGRADED` dependency ухудшает зависимую subsystem; `OFFLINE` dependency отключает её.
7. Повреждение sensor не должно удалять независимую locomotion.
8. Потеря power/control должна каскадно отключать drive.
9. `IMMOBILE` profile не содержит locomotion/steering capabilities.
10. Command pin-ит profile checksum и отклоняется после изменения конструкции.
11. Actor получает command только при полном наборе requirements.
12. Same-revision mutation и stale profile fail closed.
13. Persistence load транзакционен; profile можно полностью rebuilt из snapshot.
14. C6 не двигает physics body и не создаёт альтернативную authority boundary.

### Контрольный vertical slice

Колёсный rover состоит из chassis, четырёх wheels, battery, controller и sensor array. `DRIVE` требует quorum 2/4. Потеря одного wheel даёт `DEGRADED` и уменьшает effective speed по health ratio. Потеря трёх wheels делает rover `IMMOBILE`, но оставляет scan при здоровом sensor. Sensor failure убирает только perception. Battery/controller failure каскадно отключает зависимые subsystems. Repair с новой construct revision восстанавливает полный профиль и команды.

**Статус:** ACCEPTED.

## C7 — Spatial Construct

Небольшой дом: foundation, floor, четыре стены, roof, exterior door/window, semantic room, power и data. Проверяются Space Graph, enclosure, utility dependencies и activation LOD.

### Контракты

- `ConstructionSpatialSectionDefinition/State`;
- `ConstructionSpatialOpeningDefinition/State`;
- `ConstructionSpatialSpaceDefinition/State`;
- `ConstructionSpatialUtilityDefinition/State`;
- `ConstructionSpatialProfile`;
- profile store, persistence и checksum-pinned commands.

### Инварианты

1. Space, section, opening и utility IDs уникальны и отсортированы.
2. Все references разрешаются в concrete parts/bonds или другие spatial definitions.
3. Utility dependency graph не содержит циклов.
4. Exterior breach делает помещение `EXPOSED`.
5. Открытая исправная дверь даёт `DEGRADED`, но сохраняет occupancy.
6. Utility failure не разрушает enclosure.
7. `INACTIVE` profile не публикует capabilities/affordances.
8. Stale и same-revision profile mutation fail closed.
9. Persistence load транзакционен; profile полностью rebuilt из snapshot.
10. C7 не делает mesh, navigation или door animation authoritative.

### Контрольный vertical slice

Intact house компилируется в `ACTIVE/HABITABLE/FUNCTIONAL`. Open door даёт `DEGRADED` и `CLOSE_DOOR`. Потеря wall/window/door bond даёт `EXPOSED/INACTIVE/SUMMARY`. Потеря power отключает power и dependent data, но сохраняет shelter. Repair с новой revision восстанавливает полный profile.

**Статус:** ACCEPTED.

## C8 — Fabrication Cell

Производственная ячейка превращает реальные item inputs в новые item outputs, не создавая отдельную производственную identity и не обходя C2A/C2B authority boundary. Изготовленный предмет возвращается в обычный Item Graph и может быть использован тем же C3 BuildPlan, который исполняет игрок или builder agent.

### Контракты

- `ConstructionFabricationRecipe` и immutable versioned catalog;
- `ConstructionFabricationMachineDefinition/Profile`;
- `ConstructionFabricationJob` и priority queue;
- fabrication persistence;
- transaction planner reserve/complete/release;
- generic fabrication agent.

### Инварианты

1. Recipe, machine, job, catalog и queue имеют строгие schema/checksum.
2. Job закрепляет точные recipe version/checksum, machine profile checksum и item bindings.
3. Input/output IDs уникальны и канонически отсортированы.
4. Reservation только перемещает реальные входы в machine input container.
5. Completion одним планом расходует входы, создаёт выходы и обновляет machine construct.
6. Exact stack consumption удаляет item; partial consumption увеличивает revision и уменьшает quantity.
7. Fabricated output создаётся только в container relation и несёт `fabrication_origin`.
8. Cancel возвращает зарезервированные предметы в исходные relations без изменения quantities.
9. Progress operations идемпотентны и конфликтуют при повторном ID с другим payload.
10. Offline machine не резервирует входы и не продвигает работу.
11. Crash после authoritative completion восстанавливается без второго расхода и выпуска.
12. Integral float/int DTO сравниваются через canonical JSON.
13. Catalog/queue persistence load транзакционен.
14. C8 не делает визуальную анимацию, physics-process или network command endpoint authoritative.

### Контрольный vertical slice

Powered CNC cell резервирует `coolant ×1` и `steel_ingot/S355 ×3`, выполняет десять work units и выпускает `beam ×1`. Полный coolant stack удаляется, steel stack уменьшается `6 → 3`, output получает immutable recipe/job/machine provenance и успешно входит как source projection в C3 BuildPlan. Power loss блокирует job без изменения Item Graph; cancel возвращает сырьё; crash после completion восстанавливается через machine runtime и exact replay.

**Статус:** ACCEPTED.

## C9 — Damage, Split, Repair

1. Damage request pin-ит source construct checksum.
2. Broken/degraded bonds и part conditions применяются детерминированно.
3. Connected components считаются без `BROKEN` bonds и `DESTROYED` parts.
4. Компонента retained part остаётся source aggregate.
5. Крупные отделившиеся компоненты получают заранее закреплённые aggregate/root IDs.
6. Мелкие компоненты становятся salvage в world/container relation.
7. Source, child constructs, roots и item relations меняются в одной C2B/M0 транзакции.
8. Repair plan pin-ит original topology и реальные required item IDs.
9. Repair удаляет временные split aggregates и восстанавливает source без копирования items.
10. Damage/repair exact replay идемпотентен, operation conflicts отклоняются.
11. History/persistence и repair ghost транзакционны, но не заменяют authoritative snapshot.
12. Derived mobile/spatial/fabrication profiles перестраиваются после topology change.

### Контрольный vertical slice

Bridge-arm из шести частей теряет две связи. Source сохраняет anchor/core/joint, arm/tool образуют новый construct, sensor становится salvage. Repair возвращает все шесть исходных `ItemInstance`, удаляет временный child root, восстанавливает пять bonds и `OPERATIONAL` state.

**Статус:** ACCEPTED.

## C10 — Parametric Members

1. Versioned material definitions задают density, stock identity и массу stock unit.
2. Versioned member definitions задают exact parameter schema, defaults и limits.
3. Поддерживаются `BEAM`, `PANEL`, `PIPE`, `CABLE`, `LAYERED_WALL`.
4. Compiler детерминированно выводит geometry, volume, surface area, bounding box и mass.
5. Layered walls агрегируют per-material volume/mass по ordered layers.
6. Instance pin-ит definition version/checksum и реальный item ID.
7. Projection factory создаёт обычный Item Graph projection и semantic part record.
8. C8 recipe compiler преобразует material usage в authoritative stock requirements.
9. Fabricated member используется как source item C3 BuildPlan.
10. C5 capability описывает structural/conduit/enclosure semantics без prefab lookup.
11. Segmentation сохраняет mass, volume и per-material usage.
12. Repair plan pin-ит segment checksums и восстанавливает исходный parent instance.
13. C9 aggregate split/repair сохраняет parametric component и item identity.
14. Catalog/store persistence transactional и exact replay не меняет generation.

### Контрольный vertical slice

Параметрическая S355-балка длиной 2 м вычисляет массу и steel-stock requirements, изготавливается в принятой C8 cell, становится обычным output `ItemInstance`, входит в C3 BuildPlan, затем переносится через C9 split/repair без изменения checksum. Отдельный cut plan делит 8-метровую балку на `3 + 2 + 3 м` с полной консервацией.

**Статус:** ACCEPTED.

## C11 — Local Geometry Editing

1. Edit request pin-ит C10 member, ItemProjection и ConstructSnapshot checksums/revisions.
2. Поддержаны parameter edit и ordered control-point operations.
3. Grid snap, locks, segment limits и orthogonal path являются строгими DTO constraints.
4. Effective path length передаётся обратно в C10 compiler.
5. Mass, volume и material usage всегда пересчитываются C10, а не задаются вручную.
6. Local geometry state хранит path, bounds, edit revision, constraints и provenance.
7. Item projection, semantic part и construct snapshot обновляются одной C2A/C2B transaction.
8. Item/member/definition identities и relation остаются неизменными.
9. C5 capability и C8 fabrication recipe перестраиваются из нового member checksum.
10. Exact replay и crash recovery используют operation ledger и snapshot audit record.
11. History persistence transactional и не заменяет authoritative Item Graph.
12. Renderer mesh/collision остаются удаляемыми derived projections.

### Контрольный vertical slice

Параметрическая балка превращается в constrained polyline, меняет профиль и длину, после чего её item projection, part mass и construct snapshot обновляются атомарно. Locked-axis и invalid-length edits отклоняются без частичного commit; crash после commit восстанавливает history через exact replay.

**Статус:** IMPLEMENTED CANDIDATE.

## C12 — Multiplayer Acceptance

Два графических клиента, contention, permissions, reconnect, replay, checksum convergence и отсутствие двойного расхода.

## C13 — Federated Large Constructs

Section aggregates, building coordinator, cross-section ports, spatial authority и compute-worker proposals.

## Gate C7 → C8

C7 реализован после внешнего PASS C6. C8 начинается после внешнего PASS C7:

```text
Focused C1
Focused C2A
Focused C2B
Focused C3
Focused C4
Focused C5
Focused C6
Focused C7
Network/runtime regression
World regression including C3, C4, C5, C6 and C7 scenarios
Main-scene CLI
```


## Gate C8 → C9

C9 начинается только после внешней приёмки C8:

```text
Focused C1
Focused C2A
Focused C2B
Focused C3
Focused C4
Focused C5
Focused C6
Focused C7
Focused C8
Network/runtime regression
World regression including C3–C8 scenarios
Main-scene CLI
```


## Gate C9 → C10

C10 начинается только после внешней приёмки C9:

```text
Focused C1–C9
C2B authoritative multi-aggregate profile
Network/runtime regression
World regression including C3–C9 scenarios
Main-scene CLI
```


## C12 — Multiplayer Construction Acceptance

1. Permission grants pin subject, construct scope, actions and permission epoch.
2. Session reconnect increments session epoch and rejects commands from old connections.
3. Commands are strictly ordered per session and protected by checksums.
4. Optimistic preconditions use construct checksum and optional server generation.
5. `BUILD_STAGE`, `EDIT_GEOMETRY`, `APPLY_DAMAGE` and `APPLY_REPAIR` reuse existing domain processes.
6. Exact command replay does not repeat authoritative mutation or publish a second event.
7. Same command ID with another checksum is rejected.
8. Gateway crash after domain commit is recovered through the domain operation ledger.
9. Successful commands publish contiguous events with canonical item+construct state bundles.
10. Reconnected replicas receive missing events and must converge to the server checksum.
11. Permission revoke and epoch advance invalidate stale clients.
12. Gateway/session/permission persistence is transactional and tamper-checked.

### Контрольный vertical slice

Два клиента строят первую стадию C3, конкурируют за один C11 geometry edit, затем выполняют C9 damage/repair. Устаревшая команда второго клиента отклоняется, crash после authoritative edit восстанавливается без второго commit, reconnect догоняет event stream, а обе replicas получают checksum authoritative bundle.

**Статус:** IMPLEMENTED CANDIDATE.

## После C12

Каноническое подробное описание C13–C22 находится в `docs/plans/CONSTRUCTION_POST_C12_ROADMAP_RU.md`.
