# Контракт `lunar.partition.v1`

`LunarZoneManager.create_partition_snapshot()` возвращает диагностический
snapshot текущего локального окна.

```json
{
  "schema": "lunar.partition.v1",
  "active_zone": "zone/f4/17/09",
  "active_chunk": "zone/f4/17/09/chunk/03/28",
  "observer": "player",
  "zones": [
    {
      "zone_id": "zone/f4/17/09",
      "activity": 1,
      "owner_token": "local-process",
      "chunks": [
        {
          "chunk_id": "zone/f4/17/09/chunk/03/28",
          "activity": 1,
          "owner_token": "local-process",
          "terrain_revision": 0,
          "entity_count": 0
        }
      ]
    }
  ]
}
```

## Назначение v1

- диагностика разбиения;
- будущие snapshot-тесты;
- подготовка persistence;
- проверка стабильности адреса после render-origin shift.

Контракт пока не является сетевым API и может расширяться. Поля `schema`,
`zone_id`, `chunk_id`, `owner_token` и `terrain_revision` считаются фундаментом.
