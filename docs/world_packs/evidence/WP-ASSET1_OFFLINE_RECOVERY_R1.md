# WP-ASSET1 — Evidence: OFFLINE_REUSE_AND_CORRUPTION_RECOVERY

- Track: `WP-ASSET1`
- Branch: `work/world-packs-asset1-safe-fetch-r1`
- Implementation HEAD: `1ff25c9a4d6851aac7a957b9feab01e550ebdf6b`
- Milestone: `OFFLINE_REUSE_AND_CORRUPTION_RECOVERY`
- Дата (UTC): 2026-09-05

## Что реализовано

`tools/world_packs/asset_fetch/pipeline.py` — cache-first obtain:

- cache hit → байты возвращаются из raw cache, транспорт НЕ
  вызывается вообще (полностью offline reuse; источник `cache`);
- cache miss → ровно один bounded fetch через инжектированный
  транспорт → verify (size+sha256) → write-once в кэш (источник
  `network`); повторный obtain — уже из кэша;
- обнаружена порча блоба (`CACHE_CORRUPT` из get_verified) →
  quarantine повреждённого файла в `<root>/quarantine/<sha>.corrupt`
  (без слепого удаления) → ровно один повторный fetch → замена
  (источник `recovered`); последующие чтения — снова из кэша;
- typed failures: `FETCH_FAILED` (transport/verification),
  `RECOVERY_FAILED` (порча + неудачный refetch), `CACHE_WRITE_FAILED`,
  `CACHE_READ_FAILED`, `QUARANTINE_SOURCE_MISSING`.

## Тесты (offline, counting transports)

`tests/world_packs/asset_fetch/test_pipeline.py` (6 тестов): cache
hit без единого вызова транспорта; miss → один fetch → последующий
reuse (calls=1); corruption → recovered → quarantine-файл содержит
именно повреждённые байты → повторное чтение из кэша; порча +
плохой refetch → `RECOVERY_FAILED`; transport exception →
`FETCH_FAILED`; tampered refetch → `FETCH_FAILED`.

## Запущенные проверки (точный HEAD `1ff25c9a`)

```
python -m pytest tests/world_packs/asset_fetch -q
99 passed
```
