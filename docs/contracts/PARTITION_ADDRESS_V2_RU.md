# Контракт `planet_simulator.partition_address.v2`

## Назначение

`PartitionAddress` задаёт стабильный дискретный адрес данных и исключает
коллизии одинаковых координат Земли, Луны, других Вселенных, параллельных
simulation instances и разных ревизий координатной сетки.

## Каноническая cube-sphere схема

```json
{
  "schema": "planet_simulator.partition_address.v2",
  "universe_id": "main",
  "instance_id": "persistent",
  "space_id": "moon",
  "partition_scheme": "cube_sphere",
  "partition_scheme_revision": 1,
  "face": 4,
  "zone_x": 17,
  "zone_y": 9,
  "chunk_x": 3,
  "chunk_y": 28,
  "zone_id": "universe/main/instance/persistent/space/moon/partition/cube_sphere/revision/1/zone/f4/17/09",
  "chunk_id": "universe/main/instance/persistent/space/moon/partition/cube_sphere/revision/1/zone/f4/17/09/chunk/03/28"
}
```

## Значение namespace

```text
universe_id                  логическая Вселенная
instance_id                  конкретная постоянная или сценарная копия
space_id                     authority/partition domain: earth, moon, transit
partition_scheme             алгоритм дискретизации
partition_scheme_revision    ревизия параметров и семантики сетки
```

`SpatialRef.space_id=sol` и `PartitionAddress.space_id=moon` не противоречат
друг другу. Первое поле выбирает FrameGraph, второе — серверную область данных.

## Почему revision входит в ID

Плотность сетки является частью её семантики. Например, изменение
`zones_per_face` с 48 на 96 означает, что прежний `zone_x=17` покрывает другую
область поверхности. Поэтому ревизия присутствует одновременно:

- в структурном адресе;
- в строковом `zone_id/chunk_id`;
- в каталоге persistence;
- в world manifest;
- в journal events;
- в runtime snapshot.

Любое несовместимое изменение `body_radius_m`, `zones_per_face`,
`chunks_per_zone`, ориентации граней или правила округления требует повышения
`partition_scheme_revision`.

## CubeSphereGrid

Математика сетки вынесена из лунного runtime в общий модуль:

```text
scripts/simulation/partition/cube_sphere_grid.gd
```

Его дескриптор:

```json
{
  "schema": "planet_simulator.cube_sphere_grid.v1",
  "scheme_id": "cube_sphere",
  "scheme_revision": 1,
  "body_frame_id": "body/moon/fixed",
  "body_radius_m": 1737400.0,
  "zones_per_face": 48,
  "chunks_per_zone": 32
}
```

Конфигурации первой версии:

```text
config/partitions/moon_surface.json
config/partitions/earth_surface.json
```

`LunarZoneManager` является адаптером лунного runtime над общим
`CubeSphereGrid`; он больше не содержит собственную cube-sphere математику и не
фиксирует плотность сетки константами.

## Отдельный partition frame

Runtime partition обязан объявить:

```text
partition_frame_id = body/moon/fixed
```

Адрес нельзя вычислять непосредственно из координаты в `sol.barycentric` или
`body/moon/inertial`. Сначала выполняется преобразование в объявленный frame.

## Файловое представление

Текущий локальный адаптер формирует путь:

```text
partitions/main/persistent/moon/cube_sphere_r1/
face_4/zone_17_09/chunk_03_28.json
```

Это реализация storage adapter, а не сетевой протокол.

## Инварианты

1. Полный ID содержит `universe_id`, `instance_id`, `space_id`, scheme и revision.
2. Partition address не определяет reference frame сам по себе.
3. `CubeSphereGrid.body_frame_id` обязан совпадать с `partition_frame_id` runtime.
4. Render LOD и partition address независимы.
5. Authority owner не является частью стабильного адреса.
6. Смена сервера-владельца не меняет `chunk_id`.
7. Production и test scenario обязаны иметь разные `instance_id`.
8. Несовместимое изменение сетки обязательно повышает scheme revision.
9. Namespace IDs канонизируются в lower-case и не допускают разделители пути.
10. Соседство на рёбрах и углах граней вычисляется топологически через общий
    cube-sphere resolver, а не приближённым метрическим сдвигом.
11. Неверный grid descriptor или namespace останавливает инициализацию; fallback
    на лунные defaults запрещён.
12. Другие пространства могут применять `sparse_cartesian`, `orbital_sector` или
   `interior_grid` со своими ревизиями.

## Миграция

Поддерживается чтение исходного ID:

```text
zone/f4/17/09/chunk/03/28
```

раннего namespaced ID без instance:

```text
universe/main/space/moon/partition/cube_sphere_v1/zone/f4/17/09/chunk/03/28
```

и namespaced ID с instance, но без отдельного сегмента revision:

```text
universe/main/instance/persistent/space/moon/partition/cube_sphere_v1/zone/f4/17/09/chunk/03/28
```

Суффикс `_v1` преобразуется в:

```text
partition_scheme = cube_sphere
partition_scheme_revision = 1
```

Persistence умеет читать старый каталог `cube_sphere_v1`, после сохранения
переносит данные в `cube_sphere_r1` и удаляет устаревший файл. Новые записи
используют только полный revisioned address.


## Фиксация grid identity

Одного `partition_scheme_revision` недостаточно, если конфигурация была изменена
без её повышения. Поэтому world manifest сохраняет полный `partition_grid` и
сравнивает поля `body_frame_id`, `body_radius_m`, `zones_per_face` и
`chunks_per_zone`. Несовпадение считается ошибкой identity и не исправляется
автоматически.
