# PlanetSimulator — текущая дорожная карта

## Текущий gate — H1 candidate поверх принятого S1 fix1

```text
runtime accepted: v16.9.0-simulation-s1-distributed-compute-fix1
runtime candidate: v16.9.1-runtime-h1-playable-listen-host
accepted domain base: v16.8.5-domain-m0-aggregate-transactions
accepted transport base: v16.8.3-network-t1-multi-peer
```

```text
N0–N2 accepted
R3.1 accepted
A0 accepted
H0 accepted
A1 accepted
S0 accepted
T1 accepted
B0 accepted
M0 accepted
S1 accepted
```

S1 закрепил безопасную границу `worker computes → authority validates → M0 commits`. H1 реализует первую полную graphical gameplay vertical slice через embedded client/server boundary; после независимой приёмки работа переходит к H2.

## Утверждённая последовательность после S1

```text
S1 ACCEPTED
│
├─ H1  Playable listen-host — candidate
├─ H2  Dedicated server + 1 graphical client
├─ H3  Dedicated server + 2 graphical clients
├─ A2  Networked gameplay architecture checkpoint
│
├─ B1  NATS Core adapter
├─ B2  JetStream/outbox delivery
│
├─ P0  Population Field
├─ D1  Remote worker MVP
│
├─ N3  World Directory + 2 authorities
├─ N4  Generic object handoff
├─ N5  Seamless player handoff
└─ N6  Ghosts + interest management
```

После H3 выполняется отдельный A2 architecture audit/freeze checkpoint. Только после него начинается B1.

Основные документы:

- `docs/plans/PLAYABLE_NETWORK_MILESTONES_RU.md`;
- `docs/checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md`;
- `docs/architecture/S1_DISTRIBUTED_COMPUTE_CONTRACTS_RU.md`;
- `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`;
- `docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`.

# Дорожная карта к лунному симулятору мечты

## Видение финальной системы

Симулятор должен позволять:

- исследовать реальную Луну;
- управлять игроками и тысячами роботов;
- строить несколько баз;
- добывать и перемещать реголит;
- рыть траншеи и тоннели;
- исследовать пещеры;
- создавать энергетические, логистические и коммуникационные сети;
- подключать реальные Robot Agent/ROS 2 системы;
- проводить воспроизводимые эксперименты.

## Этап 0 — визуальный прототип

**Статус:** выполнен.

- реальный радиус Луны;
- double precision;
- camera-relative rendering;
- процедурный рельеф;
- GLOBAL/REGIONAL/LOCAL/ULTRA;
- персонаж и спектатор;
- кратеры, материалы и камни.

## Этап 1 — архитектурный фундамент мира

**Статус:** начат в v11.

- модульная структура проекта;
- cube-sphere Zone/Chunk address;
- Active/Warm окно;
- стабильный World façade;
- фундамент Entity Registry;
- архитектурная документация и ADR.

Критерий завершения:

- адрес чанка стабилен при перемещении render origin;
- несколько зон существуют одновременно в runtime;
- gameplay не зависит от старых путей скриптов.

## Этап 2 — постоянный изменяемый слой мира

**Статус:** первая рабочая итерация выполнена в v13.

- `world_id`, `world_seed`, `generator_version`;
- компонентная запись постоянной сущности;
- разреженное сохранение по чанкам;
- загрузка сущностей для Warm/Active окна;
- выгрузка сущностей ушедшего чанка;
- placement и удаление Survey Beacon;
- атомарная запись JSON;
- journal `created/removed/moved`;
- восстановление последней точки игрока;
- runtime и headless roundtrip-тест.

Процедурная поверхность не сохраняется. Авторитетный мир формируется как:

```text
процедурная основа
+ постоянные сущности
+ будущие terrain deltas
```

Критерий:

> Поставленный объект остаётся после перезапуска проекта, а удалённый не возвращается.

До полного завершения этапа остаются:

- отдельные состояния Dormant/Warm/Active для сцен сущностей;
- snapshot + journal compaction;
- миграции схем хранения;
- дополнительные типы постоянных объектов.

## Этап 2.5 — подключаемые контроллеры и взаимодействие от первого лица

**Статус:** контроллеры выполнены в v14, первая рабочая итерация взаимодействия выполнена в v15.3.

- `ControllerHost` как независимый подключаемый слой;
- JSON-профили движения и камеры;
- Lunar EVA humanoid controller;
- Lunar Jetpack controller;
- шаблон Earth humanoid;
- камеры первого и третьего лица;
- SpringArm для третьего лица;
- runtime-переключение контроллера;
- controller/camera diagnostics и интеграционные тесты;
- центральный raycast из камеры первого лица;
- общий контракт `world_interactable`;
- HUD-карточка объекта и контурная подсветка;
- `E` как основное действие;
- постоянное переключение сигнала Survey Beacon.

Критерий:

> Один Actor может менять способ движения и режим камеры без изменения Entity Registry, persistence, Zone/Chunk и процедурного мира.

До полного завершения промежуточного этапа остаются:

- placement preview и проверка допустимости размещения;
- отдельная модель рук и инструментов;
- secondary/hold interaction actions;
- controller equipment slots;
- wheel/track/flight contracts для Robot Actor;
- сохранение пользовательского выбора профиля.

## Этап 2.6 — асинхронная подгрузка рельефа

**Статус:** рабочая итерация v15.2.

Реализовано:

- отдельная Terrain Streaming Cell поверх Simulation Chunk и Render LOD;
- предиктивный запрос по касательной скорости наблюдателя;
- один CPU worker через `WorkerThreadPool`;
- data-only генерация кратеров, mesh arrays и rock descriptors;
- double-buffer: старая поверхность остаётся активной;
- staged main-thread commit;
- collision разбита на плитки;
- гистерезис и защита от перестройки в покое;
- безопасный runtime-тест `K` без смены активной поверхности;
- LRU-кэш восьми недавно посещённых LOCAL cells;
- до восьми дополнительных pinned cells с маяками;
- раннее восстановление кэшированной базы при приближении;
- специализированный JSONL performance log.

Критерий текущей итерации:

> Повторное посещение участка в пределах RAM-кэша не запускает многосекундный CPU build, а возвращение к базе с маяком использует pinned cache hit.

Остаётся:

- проверить реальный `terrain_surface_cache_hit` по логам v15.2;
- оценить расход RAM и подобрать ёмкость кэша;
- при необходимости выполнять cache activation по frame budget;
- разделить LOCAL mesh на clipmap rings;
- добавить удаляемый дисковый cache CPU-данных;
- добавить quality tiers для очень высокой скорости.


## Этап 2.7 — предметы, контейнеры и сборки

**Статус:** проверяемый фундамент v15.4.1.

Реализовано:

- стабильный `ItemInstance` и неизменяемый `ItemDefinition`;
- отношения `WORLD`, `CONTAINER`, `ATTACHMENT`, `DESTROYED`;
- единый транзакционный `ItemTransferService`;
- вложенные контейнеры и перенос заполненного контейнера целиком;
- защита от контейнерных и смешанных циклов;
- рекурсивная масса и внешний объём;
- свободное физическое представление через `RigidBody3D`;
- удаление физики при помещении в контейнер;
- жёсткое крепление модуля к сокету конструкции;
- демонтаж модуля обратно в рюкзак;
- отдельная визуальная лаборатория, доступная командой `world.load item_lab`;
- domain и scene-integration тесты.

Критерий текущей итерации:

> Один и тот же экземпляр камня, ящика или лидара сохраняет идентичность при
> переходах между миром, контейнером и конструкцией, а граф отношений остаётся
> непротиворечивым.

До следующей итерации остаются:

- сохранение предметного домена в persistent world;
- взаимодействие лучом вместо лабораторных кнопок;
- слоты экипировки и быстрый доступ;
- placement preview для устанавливаемых предметов;
- динамические/шарнирные крепления;
- функциональные power/data/mechanical графы сборок.

## Этап 2.8 — общее ядро симулятора, миры, команды и регрессия

**Статус:** первый рабочий вертикальный срез выполнен в v15.5.

Реализовано:

- `SimulatorApp` как единая точка входа над конкретными картами;
- JSON-каталог подключаемых миров;
- отдельные конфигурации `moon`, `earth`, `earth_moon`, `item_lab`,
  `playground`;
- отдельный `EarthApp`, который не создаёт скрытый Lunar runtime;
- единый lifecycle загрузки и выгрузки runtime;
- общий `CommandRegistry` вместо роста несогласованных горячих клавиш;
- общие `world.*`, `input.*` и `display.*` команды принадлежат ядру;
- классическая текстовая консоль по `~`;
- aliases, кавычки, история и автодополнение;
- owner-based очистка команд и тестов при смене мира;
- атомарная проверка регистрации команд/тестов без частично активного runtime;
- runtime-тесты, запускаемые внутри игры;
- headless boot matrix всех начальных миров с проверкой обязательных и
  запрещённых команд;
- body-isolation тест, подтверждающий отсутствие Луны в мире `earth`;
- плоский тестовый humanoid через существующий `ControllerHost`;
- закрытая площадка для экспериментов и движения персонажа.

Критерий текущей итерации:

> Любая начальная карта загружается через одно ядро, использует общую систему
> команд и управления, регистрирует собственный smoke-тест и не оставляет свои
> обработчики после переключения на другой мир.

До полного завершения слоя остаются:

- декларативные переназначаемые command bindings;
- роли и разрешения команд;
- файлы сценариев автоматизации и JUnit/JSON-отчёты;
- пользовательские world packs и hot reload каталога;
- формальный адаптер версий `WORLD_RUNTIME`;
- визуальный браузер миров поверх командного API.

## Этап 2.9 — координаты, движение и distributed-ready пространство

**Статус:** зафиксированный локальный фундамент выполнен в v15.5.1-fixed.

Реализовано:

- единые `SimulationClock` выше runtime миров;
- time-dependent `FrameGraph`;
- `SpatialRef` с universe/instance/space/frame/position/orientation/velocity/time;
- аналитические static/circular/Kepler orbit providers;
- static/uniform/tidally-locked rotation providers;
- body-fixed и body-centered inertial frame Земли и Луны;
- observer reference frame без переписывания координат поверхности;
- namespaced `PartitionAddress v2` с `universe/instance/space`;
- отдельные `partition_scheme` и `partition_scheme_revision` в каноническом ID;
- универсальный конфигурируемый `CubeSphereGrid` для разных тел;
- явный `partition_frame_id`;
- entity authority owner, epoch fencing и атомарная spatial revision;
- разные операции authoritative delete и replica eviction;
- несколько interest sources для игроков, роботов и pinned sites;
- чтение legacy entity/chunk IDs и старых файлов сохранения;
- миграция старого `cube_sphere_v1` каталога в revisioned storage;
- headless-тесты преобразований, движения тел и миграции partition;
- топологические переходы zone/chunk через все грани cube-sphere;
- fail-closed настройка partition runtime без скрытого fallback;
- полная очистка legacy-файлов после миграции и удаления сущности.

Критерий:

> Неподвижный объект поверхности сохраняет постоянные body-fixed координаты при
> орбитальном движении и вращении тела; переход в другой reference frame не
> меняет физическое состояние; одинаковый адрес чанка разных тел не конфликтует.

До реального выделения процессов остаются:

- command envelope и operation ledger;
- authority handoff state machine;
- in-process Earth/Moon/Transit authority test;
- agreed handoff frame и ghost replication;
- persistence ports вместо прямой зависимости от файлов;
- аналитическое состояние корабля и promotion в локальную физику;
- системная эфемеридная authority и revision конфигурации.

Подробности:

- `docs/architecture/REFERENCE_FRAMES_AND_DISTRIBUTED_SPACE_RU.md`;
- `docs/contracts/SPATIAL_REF_V1_RU.md`;
- `docs/contracts/PARTITION_ADDRESS_V2_RU.md`;
- `docs/contracts/ENTITY_STATE_V2_RU.md`;
- `docs/plans/V15_5_1_COORDINATE_FOUNDATION_PLAN_RU.md`.

## Этап 3 — первая локальная база

- Site как группа зон;
- строительная сетка и sockets;
- habitat, storage, solar panel, charger;
- power graph;
- inventory и ресурсы;
- режим строительства игроком.

Критерий:

> Игрок строит функционирующую маленькую базу из нескольких модулей.

## Этап 4 — первый автономный ровер

- Robot Entity;
- capability manifest;
- локальная навигация;
- аккумулятор;
- зарядка;
- доставка груза;
- телеметрия и replay.

Критерий:

> Ровер самостоятельно выполняет цикл доставка → зарядка → новая задача.

## Этап 5 — флот и локальная диспетчеризация

- 10–50 роботов;
- граф проходимости;
- приоритеты задач;
- предотвращение конфликтов;
- упрощённый локальный RMF слой;
- разные уровни fidelity.

## Этап 6 — изменяемая поверхность

- terrain delta per chunk;
- траншеи и насыпи;
- добыча материала;
- уплотнение грунта;
- масса и объём реголита;
- сохранение ревизий.

Критерий:

> Робот выкапывает траншею, а изменение сохраняется и влияет на проходимость.

## Этап 7 — тоннели и пещеры

- sparse voxel/SDF chunks;
- Marching Cubes или Dual Contouring;
- подземная локализация;
- lidar и карта неизвестности;
- опоры и риск обрушения;
- подземные коммуникации.

## Этап 8 — развитая база

- power/data/life-support/logistics graphs;
- шлюзы и герметичные объёмы;
- ремонт и деградация;
- производство;
- автоматическое обслуживание роботами.

## Этап 9 — несколько баз в одном офлайн-мире

- несколько Site Runtime;
- разные уровни активности;
- межбазовые миссии;
- фоновые аналитические роботы;
- транспорт между удалёнными районами.

На этом этапе проект всё ещё может работать в одном процессе или на одной
машине.

## Этап 10 — выделение процессов

Только после стабилизации локальных контрактов:

- Site Runtime в отдельном процессе;
- передача владения сущностями;
- локальный IPC;
- восстановление после падения;
- deterministic snapshot/replay.

## Этап 11 — сетевой мир и горизонтальное масштабирование

- World Router;
- Site Servers;
- серверное владение зонами;
- interest management;
- distributed persistence;
- динамический запуск горячих участков;
- тысячи фоновых и сотни активных роботов.

## Этап 12 — научный и hardware-in-the-loop режим

- NASA LOLA/DEM;
- реальные координаты известных объектов;
- реалистичная солнечная геометрия;
- термические циклы;
- связь и задержки;
- модели сенсоров;
- подключение физических роботов;
- сравнение симуляции с реальными логами.

## Антицели

Проект не должен одновременно пытаться реализовать:

- полноценную сеть;
- воксельную Луну целиком;
- тысячу физических роботов;
- сложную экономику;
- атмосферную/термическую науку;
- фотореалистичный рендер всех масштабов.

Каждый этап должен завершаться рабочим вертикальным срезом.


## Текущее состояние: v16.5.2-foundation-network-n1

Приняты Foundation/N0, Inventory UI-I0–UI-I2, N1.0 transport boundary, N1.1 ENet snapshot и N1.2 authoritative item command. Текущий candidate N1.3 завершает N1 reconnect/replay:

```text
commit item mutation
→ потеря command result
→ новая transport session
→ resume ticket + same operation_id
→ cached result/delta
→ mutation/ledger остаются равны 1
```

## Текущий главный приоритет: принятие N1.3

Обязательный gate:

- logical session сохраняется, transport session ротируется;
- resume ticket и replay cache bounded;
- command fingerprint, client identity и checksum fenced;
- два reconnect не вызывают второй domain handler;
- клиент применяет delta только один раз;
- полный network/world regression проходит.

## Затем: R3.1 → N3 → N4 → N5

### N2 — multi-process harness

Единый кроссплатформенный runner: динамические порты, isolated `user://`, readiness, timeouts, cleanup, fault scenarios, JSON/JUnit.

### R3.1 — authoritative persistence/recovery

Replay/dedup records, ledger и snapshot переживают restart; тот же `operation_id` возвращает прежний terminal result без mutation.

### N3 — World Directory

Node registration, heartbeat, authority lease/route и epoch fencing.

### N4 — cross-server handoff

Make-before-break transfer с одним active authoritative writer.

## Отложено до N1/N2

- UI-I3 batch/multi-select;
- take-all/deposit-all;
- prediction;
- ghosts;
- второй authoritative server;
- dynamic region split.

## Обязательные архитектурные инварианты

```text
canonical simulation ≠ presentation ≠ transport
```

- один authoritative owner;
- owner change всегда повышает `authority_epoch`;
- `state_revision` и `server_tick` не откатываются;
- UI отправляет команды и не мутирует домен;
- offline и network используют одинаковые command handlers;
- persistent/network payload не содержит scene/runtime objects.

Каждый следующий этап завершается автоматическим вертикальным тестом и оставляет
offline mode рабочим.
