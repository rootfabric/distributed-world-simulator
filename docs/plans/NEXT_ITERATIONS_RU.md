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
| `v15.7.0-r1.2` | текущий чекпоинт | expected revision, payload fingerprint и persistent operation ledger |
| `v15.8-r1.3` | следующий срез | world physics policy и рекурсивная физическая масса |
| `v16` | после v15.6 | первая локальная база |

Текущий обязательный барьер — приёмка `v15.7.0-r1.2` поверх зелёного
R1.1: editor import/parse, полный набор из 27 headless-тестов, persistent replay
после restart и main-scene regression. Чекпоинты:
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

**Статус:** реализовано, требуется приёмочный прогон на целевой double build.

- optimistic `expected_revision` для move и split;
- canonical SHA-256 payload fingerprint;
- exact replay без повторной мутации;
- `OPERATION_ID_CONFLICT` для другого payload;
- `REVISION_CONFLICT` для stale write;
- bounded versioned operation ledger;
- terminal/retryable error semantics;
- persistence через ItemStateStore и replay после restart;
- отдельный regression test.

Следующий шаг: R1.3 — world-specific gravity/physics environment и рекурсивная
физическая масса контейнеров.

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
