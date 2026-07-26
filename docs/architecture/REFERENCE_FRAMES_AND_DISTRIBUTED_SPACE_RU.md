# Иерархические системы отсчёта и распределённое пространство

## Назначение

Этот документ фиксирует координатный фундамент PlanetSimulator, на котором
должны строиться движение небесных тел, поверхность, корабли, persistence и
будущее горизонтальное масштабирование.

Главное правило:

> Каноническое состояние объекта хранится в явно указанной системе отсчёта.
> Положение узла Godot является только локальным представлением этого состояния.

Нельзя использовать одно поле `global_position` одновременно как:

- физическую координату во Вселенной;
- координату поверхности планеты;
- адрес серверного владения;
- координату рендера возле камеры.

Эти четыре понятия разделены.

## Четыре независимых пространства

### 1. Universe instance и reference frame

Перед математикой frame определяется идентичность пространства:

```text
universe_id = main
instance_id = persistent
space_id = sol
```

`instance_id` разделяет постоянную Вселенную, тестовый сценарий и параллельную
копию симуляции. Ни `FrameGraph`, ни persistence не должны смешивать ссылки из
разных instances.

`frame_id` определяет математическую систему отсчёта:

```text
sol.barycentric
body/earth/inertial
body/earth/fixed
body/moon/inertial
body/moon/fixed
```

Преобразование между frame зависит от абсолютного времени симуляции.

### 2. Coordinate space и authority domain

В `SpatialRef` поле `space_id` означает coordinate-space/frame-graph domain:

```text
sol
alpha_centauri
```

В `PartitionAddress` поле `space_id` означает partition domain внутри этой
Вселенной:

```text
earth
moon
transit
```

Server authority хранится отдельно как `authority_owner_id`. Корабль может иметь
`SpatialRef.space_id=sol`, `frame_id=sol.barycentric`, partition `transit` и
временно принадлежать authority `transit-02`.

### 3. Simulation partition

`PartitionAddress` определяет дискретный адрес данных:

```text
universe/main/instance/persistent/space/moon/partition/cube_sphere/revision/1/
zone/f4/17/09/chunk/03/28
```

Partition вычисляется только в объявленном `partition_frame_id`. Для лунной
поверхности это `body/moon/fixed`. Координату из другого frame необходимо сначала
преобразовать через `FrameGraph`.

### Универсальная сетка поверхности

Cube-sphere математика находится в общем модуле
`scripts/simulation/partition/cube_sphere_grid.gd`. Конкретное тело задаёт
дескриптор `scheme_id`, `scheme_revision`, `body_frame_id`, `body_radius_m`,
`zones_per_face` и `chunks_per_zone`. Лунный runtime только подключает этот
resolver и управляет interest window.

Ревизия сетки является частью канонического адреса:

```text
.../partition/cube_sphere/revision/1/zone/...
```

Это предотвращает тихую переинтерпретацию старых данных после изменения
плотности, ориентации граней или правил округления.

### 4. Render frame

Godot, GPU и локальная физика получают координаты возле нуля:

```text
render_position = point_in_observer_frame - render_origin
```

Смена render origin не меняет `SpatialRef`, partition или authority.

Локальный файловый adapter сохраняет совместимый путь `user://worlds/...` для
`main/persistent`, чтобы не потерять существующие сохранения. Любой другой
`instance_id` получает отдельный корень
`user://universes/<universe>/instances/<instance>/worlds/...`; chunk IDs,
manifest и journal несут ту же identity.

## Дерево frame первой версии

```text
sol.barycentric
├── body/sun/inertial
│   └── body/sun/fixed
├── body/earth/inertial
│   ├── body/earth/fixed
│   └── body/moon/inertial
│       └── body/moon/fixed
```

Текущая конфигурация упрощённо связывает Луну с земным инерциальным frame.
Контракты допускают последующее добавление:

```text
sol.barycentric
└── earth_moon.barycentric
    ├── body/earth/inertial
    └── body/moon/inertial
```

Добавление барицентра не требует изменения координат объектов поверхности:
они продолжают храниться в `body/earth/fixed` и `body/moon/fixed`.

## Состояние frame

Каждый frame предоставляет относительно родителя:

```text
origin_parent_m
basis_parent_from_child
linear_velocity_parent_mps
angular_velocity_parent_rps
```

`FrameGraph` компонует цепочку до корня и умеет преобразовывать:

- точки;
- направления;
- ориентацию;
- линейную скорость с членом `ω × r`;
- угловую скорость;
- полный `SpatialRef`.

Это важно при старте с поверхности. Объект, неподвижный в
`body/earth/fixed`, имеет ненулевую скорость в `sol.barycentric` из-за вращения
и орбитального движения Земли.

## Единые часы

`SimulationClock` находится выше runtime конкретной карты и хранит:

```text
authority_id
authority_epoch
epoch_seconds
simulation_time_s
time_scale
paused
tick_index
time_revision
```

Орбиты и вращения вычисляются как функция абсолютного времени:

```text
state = provider.sample_state(simulation_time_s)
```

Запрещён канонический расчёт небесных тел через накопление
`position += velocity * delta`: он зависит от частоты кадров, накапливает ошибку
и плохо синхронизируется между серверами.

Clock snapshot принимается через `apply_authoritative_snapshot`. Fencing использует
`authority_epoch`, а внутри текущей эпохи отвергаются меньшие `time_revision` и
`tick_index`. Поэтому запоздалый EphemerisAuthority не может откатить время после
переключения владельца. Сетевой transport пока не реализован.

## Providers движения

`CelestialSystem` не содержит формулу конкретной орбиты. Он строит frame graph
из подключаемых providers.

### OrbitProvider

Реализованы:

- `static`;
- `circular`;
- `kepler`.

Предусмотрены будущие адаптеры:

- tabulated ephemeris;
- SPICE-подобная эфемерида;
- локальный N-body интегратор.

### RotationProvider

Реализованы:

- `static`;
- `uniform` с наклоном оси;
- `tidally_locked`.

## Где хранить разные объекты

| Объект | Канонический frame |
|---|---|
| Здание на Земле | `body/earth/fixed` |
| Камень на Луне | `body/moon/fixed` |
| Спутник Земли | `body/earth/inertial` |
| Корабль в перелёте | `sol.barycentric` |
| Предмет в контейнере корабля | без независимой мировой позиции; relation к aggregate |
| Локальный узел Godot | observer/render frame |

## Наблюдатель

`EarthExplorer` хранит:

```text
reference_frame_id
frame_position
orientation
linear_velocity_mps
angular_velocity_rps
```

Переключение frame выполняется с сохранением физического состояния через
`transform_spatial_ref`. Это не телепортация и не пересоздание персонажа.
Преобразование выполняется в `sample_time_s` состояния; продвижение состояния к
другому времени принадлежит motion model наблюдателя или корабля.

Рекомендуемые режимы:

```text
поверхность       → body/<body>/fixed
околопланетный    → body/<body>/inertial
межпланетный      → sol.barycentric
```

## Связь с серверным масштабированием

Frame graph является общей математической моделью, а не сетевым topology graph.
Серверы могут владеть разными областями одного frame или несколькими frame.

Первая практичная схема:

```text
UniverseDirectory
├── EphemerisAuthority: Sol
├── EarthAuthority
├── MoonAuthority
└── TransitAuthority
```

`EphemerisAuthority` распространяет только:

- `authority_id/authority_epoch`;
- epoch/config revision;
- simulation time, tick и time scale;
- параметры providers.

Клиенты и серверы аналитически получают согласованные положения крупных тел. Нет
необходимости передавать положение Земли и Луны каждый physics tick. При этом
результат floating-point вычислений не считается побитово детерминированным между
всеми платформами: authority передаёт epoch/config revision, а сетевые проверки
используют допустимую погрешность и authoritative snapshots.

## Движение через серверные границы

Reference frame и authority boundary независимы. Выход корабля из лунной области
не обязан менять `frame_id` в ту же секунду, а смена observer frame не означает
handoff. Для практической Earth/Moon/Transit схемы используется зона гистерезиса:

```text
MoonAuthority owns aggregate
→ объект входит в outbound handoff band
→ TransitAuthority получает snapshot и создаёт ghost
→ directory фиксирует новый owner/epoch
→ TransitAuthority становится authoritative
→ MoonAuthority временно оставляет read-only ghost
→ старая replica удаляется
```

Граница не проводится через активно взаимодействующую физическую группу.
Корабль, joints, пассажиры, прикреплённые модули и контейнерное дерево переходят
как один authority aggregate.

## Handoff объекта

Перед передачей объект преобразуется в agreed handoff frame, обычно системный
инерциальный frame:

```text
body/moon/fixed
→ body/moon/inertial
→ sol.barycentric
→ TransitAuthority
```

Snapshot обязан содержать:

```text
entity_id
SpatialRef
authority_owner_id
authority_epoch
state_revision
aggregate contents
operation_id
```

После подтверждения целевой сервер повышает `authority_epoch`. Любая запись от
старого owner отвергается fencing-проверкой.

## Физические группы

Граница authority не должна проходить через активно взаимодействующую группу.
Вместе передаются:

- корабль;
- пристыкованные модули;
- пассажиры;
- вложенные контейнеры;
- прикреплённые предметы;
- объекты, удерживаемые joint/манипулятором.

Это authority aggregate. Распределённая физика столкновения между двумя
серверами не является целью базового слоя.

## Текущее ограничение v15.5.1

Реализован локальный фундамент, но пока не реализованы:

- отдельные процессы;
- сетевой протокол;
- handoff coordinator;
- EphemerisAuthority;
- client prediction;
- динамическое владение чанками;
- N-body providers;
- барицентр Земля–Луна;
- локальная promotion аналитического объекта в физику.

Это намеренное ограничение. Локальные контракты должны быть проверены до
появления транспорта, постоянных контейнеров и строительства.
