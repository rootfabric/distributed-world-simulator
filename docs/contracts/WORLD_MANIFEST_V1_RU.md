# Контракт `lunar.world.v1`

Файл локального storage adapter для текущего совместимого instance
`main/persistent`:

```text
user://worlds/<world_id>/world.json
```

Для параллельного или тестового instance используется изолированный путь:

```text
user://universes/<universe_id>/instances/<instance_id>/worlds/<world_id>/world.json
```

Явный `root_override` сохраняется без изменений и считается ответственностью
вызывающего теста или внешнего storage adapter.

Минимальная структура текущей версии:

```json
{
  "schema": "lunar.world.v1",
  "world_id": "moon-experiment-001",
  "universe_id": "main",
  "instance_id": "persistent",
  "partition_space_id": "moon",
  "partition_scheme": "cube_sphere",
  "partition_scheme_revision": 1,
  "partition_grid": {
    "schema": "planet_simulator.cube_sphere_grid.v1",
    "scheme_id": "cube_sphere",
    "scheme_revision": 1,
    "body_frame_id": "body/moon/fixed",
    "body_radius_m": 1737400.0,
    "zones_per_face": 48,
    "chunks_per_zone": 32
  },
  "world_seed": 20260724,
  "generator_version": 9,
  "created_at_utc": "...",
  "last_opened_at_utc": "...",
  "storage_policy": {
    "procedural_terrain_is_authoritative": true,
    "terrain_meshes_are_cached": false,
    "only_modified_chunks_exist_on_disk": true
  }
}
```

`world_seed` определяет конкретный процедурный мир. `generator_version`
фиксирует версию алгоритма, относительно которой были размещены объекты.

`universe_id/instance_id` являются частью идентичности сохранения. Production,
тестовая лаборатория и параллельный прогон не должны совместно использовать
один instance namespace. `partition_grid` фиксирует точную геометрию адресации:
радиус, frame и плотность ячеек. Старый manifest без этих полей читается как
`main/persistent/moon` и дополняется текущим дескриптором при миграции.

## Защита identity

При открытии существующего manifest отсутствующие legacy-поля дополняются. Если
`universe_id`, `instance_id`, `partition_space_id`, `partition_scheme`, revision
или точный `partition_grid` уже присутствуют и не совпадают с runtime, repository
прекращает инициализацию. Он не подключает lifecycle-сигналы и не выполняет
запись в чужой instance или несовместимую координатную сетку.
