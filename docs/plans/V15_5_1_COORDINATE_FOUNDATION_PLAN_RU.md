# v15.5.1 — Coordinate and Distributed-Space Foundation

## Причина этапа

После v15.5 проект готов добавлять пользовательские контейнеры, транспорт и
первые базы. До накопления постоянных данных необходимо зафиксировать, в какой
системе отсчёта хранится каждый объект и как это состояние позднее передаётся
между server authority.

Если оставить один неуточнённый `world_position`, движение планет заставит
переписывать координаты всех поверхностных объектов и приведёт к дорогой
миграции persistence.

## Решение

```text
каноническое движение      → SimulationClock + FrameGraph
состояние объекта          → SpatialRef
дискретное размещение      → PartitionAddress v2
серверное владение         → owner + authority_epoch
рендер                     → observer frame + floating origin
```

## Реализовано в этом этапе

1. Единый `SimulationClock` выше runtime миров, включая authority snapshot fencing.
2. Time-dependent `FrameGraph`.
3. Providers `static`, `circular`, `kepler`, `uniform`, `tidally_locked`.
4. Конфигурация Солнца, Земли и Луны как frame tree.
5. `SpatialRef v1` и преобразование позиции, ориентации и скоростей.
6. Наблюдатель, способный менять reference frame без телепортации состояния.
7. `PartitionAddress v2` с namespace Вселенной, instance и partition space.
8. Явный `partition_frame_id`.
9. Entity v2 с authority epoch и атомарной spatial revision.
10. Разделение authoritative delete и replica eviction.
11. Multi-source interest window для нескольких игроков/роботов.
12. Миграция старых лунных entity/chunk IDs и файловых путей.
13. Изоляция persistent/scenario instances в FrameGraph, manifest, journal и partition storage.
14. Жёсткий отказ persistence при несовпадении manifest identity.
15. Команды управления временем и frame наблюдателя.
16. Headless-тесты frame graph, орбит, clock fencing, instance isolation и partition migration.
17. Универсальный `CubeSphereGrid` вместо лунной математики и жёстких размеров.
18. Конфигурации сеток Земли и Луны как данные.
19. Scheme revision в chunk ID, manifest, journal и файловом пути.
20. Миграция `cube_sphere_v1` → `cube_sphere/revision/1` и `cube_sphere_r1`.

## Не входит в этап

- реальная сеть;
- несколько процессов;
- handoff coordinator;
- World Router;
- distributed storage;
- N-body;
- физика корабля;
- StarLightingSystem и затмения;
- динамическое распределение authority.

## Следующие архитектурные шаги

### v15.6

Пользовательские контейнеры и persistence предметов должны сохранять:

- глобально уникальный item/entity ID;
- authority aggregate root;
- SpatialRef только для WORLD relation;
- operation ledger для идемпотентных transfer;
- expected aggregate revision.

### До первого транспорта

Добавить:

- command envelope;
- authority transfer state machine;
- agreed handoff frame;
- in-process Earth/Moon/Transit authorities;
- promotion analytic state ↔ local physics state.

### Перед отдельными процессами

Добавить порты:

- `PartitionStateStore`;
- `EntityEventStore`;
- `OperationLedger`;
- `UniverseDirectory`;
- `EphemerisSource`.
