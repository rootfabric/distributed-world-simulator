# Контракт `lunar.chunk.v1`

Файл создаётся только для изменённого чанка:

```text
user://worlds/<world_id>/zones/f4_17_09/chunks/03_28.json
```

```json
{
  "schema": "lunar.chunk.v1",
  "world_id": "moon-experiment-001",
  "generator_version": 9,
  "zone_id": "zone/f4/17/09",
  "chunk_id": "zone/f4/17/09/chunk/03/28",
  "revision": 2,
  "terrain_delta_revision": 0,
  "entities": []
}
```

`entities` содержит полные snapshots постоянных сущностей. В следующих версиях список может быть заменён snapshot + journal offset без изменения адреса чанка.
