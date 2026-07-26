# Контракт `planet_simulator.spatial_ref.v1`

## Назначение

`SpatialRef` — каноническая пространственно-кинематическая ссылка объекта.
`Node3D.global_transform` является только локальным представлением возле
наблюдателя и не должен сохраняться как состояние Вселенной.

## Схема

```json
{
  "schema": "planet_simulator.spatial_ref.v1",
  "universe_id": "main",
  "instance_id": "persistent",
  "space_id": "sol",
  "frame_id": "body/moon/fixed",
  "position_m": [1737400.0, 0.0, 0.0],
  "rotation_xyzw": [0.0, 0.0, 0.0, 1.0],
  "linear_velocity_mps": [0.0, 0.0, 0.0],
  "angular_velocity_rps": [0.0, 0.0, 0.0],
  "sample_time_s": 123456.0
}
```

## Идентичность

Полный домен координаты задают три поля:

```text
universe_id   логическая Вселенная
instance_id   persistent/scenario/parallel simulation instance
space_id      домен одного FrameGraph, например sol
```

Одинаковые `frame_id` и численные координаты в разных `instance_id` не относятся
к одному пространству. `FrameGraph` обязан отвергать такое преобразование.

## Семантика

- `position_m` выражена в `frame_id`;
- quaternion задаёт ориентацию объекта относительно осей `frame_id`;
- скорости также выражены в `frame_id`;
- `sample_time_s` — момент, в котором выполняется преобразование frame;
- `space_id` определяет coordinate-space/frame-graph domain (`sol`,
  `alpha_centauri`), а не server authority;
- все линейные величины используются в SI.

`transform_spatial_ref` меняет систему отсчёта, но не интегрирует собственное
движение объекта между двумя моментами времени. Без явно переданного времени
используется собственный `sample_time_s` ссылки, а не текущее время runtime.
Интеграция корабля, персонажа
или физического тела принадлежит его motion model. Для неподвижного объекта
поверхности локальная координата остаётся постоянной в body-fixed frame, а
положение в системном frame вычисляется на нужное время.

## Инварианты

1. `universe_id`, `instance_id`, `space_id` и `frame_id` обязательны.
2. `frame_id` должен существовать в соответствующем `FrameGraph`.
3. Перед вычислением partition SpatialRef преобразуется в `partition_frame_id`.
4. Смена render origin не изменяет SpatialRef.
5. Смена reference frame с сохранением состояния преобразует позицию,
   ориентацию и обе скорости.
6. Quaternion нормализуется при создании.
7. Для предмета в контейнере предпочтительно хранить relation к authority
   aggregate, а не дублировать независимую мировую позицию.

## Миграция legacy

Старое лунное поле:

```json
{"world_position": [1737400.0, 0.0, 0.0]}
```

интерпретируется как:

```text
universe_id = main
instance_id = persistent
space_id = sol
frame_id = body/moon/fixed
```

Это правило предназначено только для чтения сохранений v1.
