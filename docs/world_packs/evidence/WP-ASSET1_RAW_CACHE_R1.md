# WP-ASSET1 — Evidence: RAW_CONTENT_ADDRESSABLE_CACHE

- Track: `WP-ASSET1`
- Branch: `work/world-packs-asset1-safe-fetch-r1`
- Implementation HEAD: `cc2c08ebb57e46cc16152230de629d15f58ac059`
- Milestone: `RAW_CONTENT_ADDRESSABLE_CACHE`
- Дата (UTC): 2026-09-05

## Что реализовано

`tools/world_packs/asset_fetch/cache.py` — immutable raw cache:

- layout `<root>/blobs/<sha[:2]>/<sha256>` (payload, write-once,
  режим 0444, O_EXCL + fsync) и `<root>/meta/<sha[:2]>/<sha256>.json`
  (provenance: asset_id/version/source_url/size, atomic replace).
- `put_verified`: адрес всегда пересчитывается из байтов; claimed
  digest других байтов → `ADDRESS_MISMATCH`; повторная запись тех же
  байтов идемпотентна; иные байты по существующему адресу →
  `IMMUTABILITY_VIOLATION`.
- `get_verified`: digest блоба перепроверяется при каждом чтении;
  повреждение на диске → `CACHE_CORRUPT` (fail-closed), отсутствие →
  `CACHE_MISS`, неинициализированный кэш → `CACHE_NOT_INITIALIZED`.

## Тесты (offline, tmp_path)

`tests/world_packs/asset_fetch/test_raw_cache.py`: roundtrip c
метаданными, идемпотентный re-put, отказ IMMUTABILITY_VIOLATION при
подмене содержимого, ADDRESS_MISMATCH (forged digest), CACHE_MISS,
CACHE_CORRUPT (битый блоб обнаружен при чтении), fail-closed на
неинициализированном кэше, права блоба 0444.

## Запущенные проверки (точный HEAD `cc2c08eb`)

```
python -m pytest tests/world_packs/asset_fetch -q
46 passed
```

Кэш живёт вне Git (tmp root), тяжёлых payloads в репозитории нет.
