# Ближайшие итерации после v15

## Динамика версий

| Версия | Состояние | Роль в проекте |
|---|---|---|
| `v15.1` | аналитический долг | разбор реальных performance logs |
| `v15.2` | реализовано | асинхронный terrain streaming и RAM cache |
| `v15.3` | реализовано | взаимодействие от первого лица |
| `v15.4.1` | реализовано | фундамент предметов, контейнеров и сборок |
| `v15.5` | реализовано | общее ядро, миры, консоль и регрессия |
| `v15.5.2-r0` | реализовано | нормализация репозитория и усиленный regression barrier |
| `v15.6.2-r1.1-fix2` | принято | глобальные item ID, versioned registry, ItemStateStore и полный SpatialRef |
| `v15.7.0-r1.2` | принято | expected revision, payload fingerprint и persistent operation ledger |
| `v15.8.1-r1.3-fix1` | принято | gravity wells, test-particle trajectories и рекурсивная физическая масса |
| `v16.0.1-r2-fix1` | принято | полный item graph, BULK/SLOTS containers, player inventory, hotbar и interaction demo |
| `v16.1.0-r2-stack-controls` | реализовано | автостак BULK, точный stack-on-stack, разделение количества через ПКМ |
| `v16.2.0-r2-placement-debug-ui` | реализовано | placeable mount item, F10 debug UI, console completion и flashlight |
| `v16.3.0-r2-inventory-ux` | базовый checkpoint | context-only external container, post-drop split UI, session-scoped operation IDs и dual-fill light |
| `v16.3.1-ui-i0` | реализовано в feature-ветке | component shell, ViewModel, CommandFacade и legacy fallback без изменения Item Graph |
| `v16.3.4-ui-i1-fix1` | принято в feature-ветке | quick transfer whole-stack semantics, context actions, explicit split, tooltip/toast и local rejection feedback |
| `v16.3.7-ui-i2-fix2` | готово к повторной приёмке в feature-ветке | UI-I2 плюс надёжная invalidation recent-operation cache при замене ledger |
| `v16.4 Foundation Gate + N0` | следующий архитектурный срез | server-safe kernel и сетевые контракты без сокетов |
| `R3.1` | параллельный gameplay-срез | foundation и строительство через доменные команды |

## Pre-roadmap UI-I0/UI-I1 — Inventory UX stabilization

**Статус:** UI-I0, UI-I1 и UI-I2 реализованы в отдельной feature-ветке; после приёмки ветка готова к merge gate.

Цель — заменить текущий монолитный presentation на hybrid two-pane grid, не
изменяя Item Graph, `ContainerState`, persistence и `ItemTransferService`.

Обязательный объём:

- динамический `BULK` без фиктивных semantic slots;
- настоящий фиксированный `SLOTS` grid;
- contextual external panel;
- LMB drag whole stack;
- Shift-click quick transfer;
- ПКМ context actions и явный split;
- tooltip/toast/local rejection feedback;
- adaptive container size;
- ViewModel и CommandFacade;
- старый facade API сохраняется.

Полный план: `docs/plans/INVENTORY_UI_REDESIGN_PLAN_RU.md`.

После UI-I2 feature-ветка проходит merge gate с основной архитектурной веткой.
UI-I3 batch/multi-select остаётся отдельной будущей веткой после появления transactional command contract.

Текущий UX-барьер — приёмка `v16.3.7-ui-i2-fix2`: editor import/parse,
полный набор из 36 headless-тестов, матрицы stack UI и context container,
проверка двухслойного фонаря, session-scoped operation IDs и main-scene playground regression. Чекпоинты:
`docs/checkpoints/2026-07-26_R0_STABILIZATION_CHECKPOINT_RU.md`,
`docs/checkpoints/2026-07-27_R1_1_ITEM_IDENTITY_STATE_STORE_RU.md` и
`docs/checkpoints/2026-07-27_R1_2_OPERATION_LEDGER_RU.md`.


## v15.6.2-r1.1-fix2 — Item identity and state store

**Статус:** принято полным item и world regression.

- UUID v4 для новых item instances;
- отдельный `display_name`;
- схемы ItemInstance/ItemRegistry/JSON state file;
- legacy load без разрушения старых ссылок;
- транзакционный registry load;
- JSON ItemStateStore;
- сохранение полного SpatialRef при capture;
- отдельный regression test.

## v15.7.0-r1.2 — Safe item operations

**Статус:** принято полным item и world regression.

- optimistic `expected_revision` для move и split;
- canonical SHA-256 payload fingerprint;
- exact replay без повторной мутации;
- `OPERATION_ID_CONFLICT` для другого payload;
- `REVISION_CONFLICT` для stale write;
- bounded versioned operation ledger;
- terminal/retryable error semantics;
- persistence через ItemStateStore и replay после restart;
- отдельный regression test.

## v15.8.1-r1.3-fix1 — Gravity wells and recursive physical mass

**Статус:** принято на целевой double build.

- общий GravityField для Солнца, Земли, Луны и будущих источников;
- inverse-square falloff и uniform-sphere interior;
- body-relative external acceleration compensation;
- velocity-Verlet test-particle propagation;
- dynamic item gravity driver;
- recursive RigidBody mass контейнеров;
- отдельные gravity и item physics regression tests.

## v16.0.1-r2-fix1 — Full item graph and player inventory

**Статус:** реализовано и самостоятельно проверено на целевой Linux double build.

- атомарный ItemGraph v1 и fail-closed staged load;
- Container v2: BULK, SLOTS, slot filters и child hotbar;
- icon inventory и drag-and-drop;
- pickup/drop/open/mount/detach;
- playground demo и стартовые лунные маяки;
- автоматические тесты сохранности, уникальности и физического presentation.

Следующий шаг: R3 — placement preview и строительные операции.

## v16.1.0-r2-stack-controls — Stack merge and split UI

**Статус:** реализовано, требуется полный целевой regression.

- ПКМ popup выбора количества следующего drag-and-drop;
- точное объединение stack-on-stack;
- частичное заполнение занятого fixed slot с остатком в source slot;
- пустой fixed slot сохраняет отдельный stack;
- BULK автоматически распределяет количество по нескольким совместимым стакам;
- STACK_ITEMS защищён source/target revision и operation ledger;
- отдельный `test_item_stack_transfers.gd`.

## v15.5.2-r0 — Stabilization checkpoint

**Статус:** изменения R0 внесены, требуется приёмочный прогон на целевой сборке.

Выполнено:

- `.godot` и `.import` исключены из репозитория;
- line endings зафиксированы через `.gitattributes`;
- добавлен однократный repository preparation script;
- regression runner проверяет полноту всех `test_*.gd`;
- editor import/parse выполняется до отдельных тестов;
- single-precision сборка отклоняется отдельным contract-тестом;
- hotkey contract включён в обязательный набор;
- добавлен тест смены мира при активной terrain generation;
- результат runner сохраняется в JSON.

Приёмка:

```powershell
.\PREPARE_R0_REPOSITORY.ps1
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

## v15.5 — Multi-world Simulator Core

**Статус:** первый вертикальный срез реализован.

Перед дальнейшим ростом предметной системы введён обязательный фундамент:

- одно ядро `SimulatorApp` для всех карт;
- каталог `moon`, `earth`, `earth_moon`, `item_lab`, `playground`;
- отдельный Earth runtime без скрытого создания Луны;
- команда `world.load` и история переходов;
- консоль по `~`;
- общие команды окна, ввода и навигации на уровне ядра;
- реестры команд и runtime-тестов с очисткой по владельцу;
- отказ от частичной загрузки при конфликте команд или тестов;
- headless boot matrix всех миров;
- отдельная закрытая площадка с общим контроллером персонажа.

Ближайшая проверка:

1. выполнить `RUN_WORLD_REGRESSION_TESTS.ps1`;
2. пройти ручную матрицу из `V15_5_ACCEPTANCE_TESTS_RU.md`;
3. проверить, что `earth` содержит только тело `earth`, а команды Луны отсутствуют;
4. все новые действия оформлять командами, а не новыми прямыми клавишами;
5. не продолжать контейнеры пользователя, пока matrix не остаётся зелёной.

## v15.6 — persistent Item Aggregate и контейнеры в закрытой площадке

- глобальные UUID/ULID для `ItemInstance`;
- persistence-port для Item Registry и Container Registry;
- revision fencing и persistent operation ledger;
- сохранение полного `SpatialRef` без потери reference frame;
- actor-owned inventory/container через существующий Item Domain;
- перенос предметов ray interaction командами;
- открытие/закрытие физического контейнера;
- проверка массы, объёма, вложенности и persistence;
- сценарий `playground` без зависимости от планетарного terrain;
- runtime и headless regression для полного цикла.

## v15.1 — анализ реальных performance logs

- пройти 2–5 км пешком и на джетпаке;
- выполнить несколько разворотов во время GENERATING;
- сопоставить `long_frame_detected` с `terrain_commit_stage`;
- определить долю CPU generation, ArrayMesh, collision и rocks;
- зафиксировать baseline для компьютера тестирования.

## v15.2 — устранение подтверждённого main-thread bottleneck

При доминировании `collision_shape`:

- разбить collision на небольшие tiles;
- подключать ближайшие tiles раньше дальних;
- заменять только вышедшие tiles;
- оставить визуальную и физическую поверхность основанными на одинаковых samples.

При доминировании `local_mesh_resource`:

- разделить LOCAL на concentric clipmap rings;
- создавать по одному ring resource за кадр;
- выполнять swap только после готовности критического внутреннего ring.

При доминировании `rock_descriptors` или `rock_layer_N`:

- отделить decoration queue от critical terrain;
- камни подключать после поверхности и collision;
- разбить крупные MultiMesh на пространственные batches.

## v15.3 — First-person Interaction

**Статус:** первая рабочая итерация реализована.

Готово:

- центральный raycast из камеры первого лица;
- контракт `world_interactable`;
- действие `E`;
- информация о Survey Beacon;
- outline/подсветка объекта;
- постоянное включение/выключение сигнала маяка;
- HUD-карточка состояния и дистанции;
- интеграционный contract-тест.

Остаётся для следующего среза:

- placement preview;
- проверка уклона и пересечений;
- secondary/hold actions;
- отдельная модель рук и инструментов.

## v16 — первая локальная база

- Foundation;
- Solar Panel;
- Battery;
- Charging Dock;
- preview и проверка уклона;
- sockets и простой power graph;
- сохранение через существующий persistent layer.

---

## Параллельный долг по фундаменту

### Chunk Lifecycle

1. Явные состояния `Dormant`, `Warm`, `Active`, `Unloading`.
2. В Warm хранить только EntityRecord без физического узла.
3. В Active создавать визуальную сцену и коллизию.
4. Очередь создания сущностей по frame budget.
5. Метрики чтения JSON и создания runtime scenes.

### Controller Layer

1. equipment slots;
2. сохранение выбранного профиля;
3. отдельные wheel/track/flight contracts для Robot Actor.
