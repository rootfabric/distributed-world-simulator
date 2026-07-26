# Контракт partition snapshot

## Текущий snapshot v2

`LunarZoneManager.create_partition_snapshot()` возвращает диагностический
snapshot локального окна интереса:

```json
{
  "schema": "planet_simulator.partition_window.v2",
  "universe_id": "main",
  "instance_id": "persistent",
  "space_id": "moon",
  "partition_scheme": "cube_sphere",
  "partition_scheme_revision": 1,
  "partition_frame_id": "body/moon/fixed",
  "authority_owner_id": "local-process",
  "active_zone": "universe/main/instance/persistent/space/moon/partition/cube_sphere/revision/1/zone/f4/17/09",
  "active_chunk": "universe/main/instance/persistent/space/moon/partition/cube_sphere/revision/1/zone/f4/17/09/chunk/03/28",
  "observer": "player",
  "interest_sources": [],
  "zones": []
}
```

Snapshot разделяет:

- identity: `universe_id/instance_id`;
- partition domain: `space_id/partition_scheme`;
- математический frame адресации: `partition_frame_id`;
- текущего владельца: `authority_owner_id`;
- объединённое окно нескольких interest sources.

Контракт диагностический и пока не является сетевым API.

## Legacy v1

Старый `lunar.partition.v1` с ID вида
`zone/f4/17/09/chunk/03/28` поддерживается только как вход миграции.
