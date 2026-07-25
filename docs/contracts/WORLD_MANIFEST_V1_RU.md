# Контракт `lunar.world.v1`

Файл:

```text
user://worlds/<world_id>/world.json
```

Минимальная структура:

```json
{
  "schema": "lunar.world.v1",
  "world_id": "moon-experiment-001",
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

`world_seed` определяет конкретный процедурный мир. `generator_version` фиксирует версию алгоритма, относительно которой были размещены объекты.
