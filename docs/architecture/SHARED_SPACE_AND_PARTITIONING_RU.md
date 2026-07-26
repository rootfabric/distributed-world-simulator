# Единое пространство Земля–Луна и последующее разбиение по серверам

## Текущая модель v15.5.1

Земля и Луна больше не хранятся как два статических центра в одном
неуточнённом `Vector3`. Они входят в time-dependent frame graph:

```text
sol.barycentric
├── body/earth/inertial
│   ├── body/earth/fixed
│   └── body/moon/inertial
│       └── body/moon/fixed
└── body/sun/inertial
    └── body/sun/fixed
```

Положение крупных тел вычисляется аналитическими providers по единому
`SimulationClock`. Surface objects остаются неподвижными в body-fixed frame.

## Почему это остаётся единым миром

Объект можно преобразовать между frame в один и тот же момент времени:

```text
moon surface SpatialRef
→ body/moon/inertial
→ sol.barycentric
→ body/earth/inertial
→ earth surface observer frame
```

Смена frame не создаёт отдельную копию объекта и не меняет его identity.
Floating origin применяется после выбора observer frame и не является границей
мира или сервера.

## Partition не равен frame

Лунные surface chunks адресуются в:

```text
partition_frame_id = body/moon/fixed
partition_scheme = cube_sphere
partition_scheme_revision = 1
```

Полный адрес:

```text
universe/main/instance/persistent/space/moon/partition/cube_sphere/revision/1/
zone/f4/17/09/chunk/03/28
```

Межпланетный transit позднее может использовать `sol.barycentric` и другую
схему, например sparse Cartesian/orbital sectors.

## Будущее серверное разбиение

```text
UniverseDirectory
├── SystemEphemerisAuthority
├── EarthAuthority
├── MoonAuthority
└── TransitAuthority
```

Рекомендуемая граница проходит через разреженное пространство, а не через базу
или физически взаимодействующую группу.

Authority handoff использует:

```text
SpatialRef
authority_owner_id
authority_epoch
state_revision
operation_id
aggregate snapshot
```

Новый authority повышает epoch. Старые команды fenced и не могут изменить
переданную сущность.

## Interest и activation

Следует различать:

```text
AuthoritySet   — чем владеет сервер
InterestSet    — что требуется конкретному клиенту/роботу
ActivationSet  — где выполняется дорогая локальная симуляция
```

`LunarZoneManager` уже поддерживает несколько interest sources и объединяет их
Warm/Active окна. Это локальный прототип будущего server interest management.

## Что не зависит от серверной границы

- GLOBAL/REGIONAL/LOCAL/ULTRA render LOD;
- terrain streaming cells;
- camera-relative origin;
- визуальный proxy далёкого тела;
- body-fixed координаты базы;
- глобальный `entity_id`.

Подробная математическая модель:
`REFERENCE_FRAMES_AND_DISTRIBUTED_SPACE_RU.md`.
