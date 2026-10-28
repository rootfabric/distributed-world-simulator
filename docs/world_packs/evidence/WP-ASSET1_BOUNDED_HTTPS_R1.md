# WP-ASSET1 — Evidence: BOUNDED_HTTPS

- Track: `WP-ASSET1`
- Branch: `work/world-packs-asset1-safe-fetch-r1`
- Implementation HEAD: `f3b6e41bb8619ba76b82c2a2121d2ddb7490a574`
- Milestone: `BOUNDED_HTTPS`
- Дата (UTC): 2026-09-05

## Что реализовано

`tools/world_packs/asset_fetch/https.py` — bounded streaming https
транспорт (stdlib-only, `urllib.request`):

- `make_bounded_transport(opener, ...)`: streaming чтение чанками с
  жёсткой границей в `expected_size_bytes` + 1 probe byte: сервер не
  может занять память/диск больше pinned размера. Коды:
  `SIZE_EXCEEDED`, `SIZE_SHORT`, `OPEN_FAILED`, `READ_FAILED`.
- `hard_max_bytes` может только сужать границу, но не расширять.
- Явный connect/read timeout (по умолчанию 15s, максимум 120s).
- Opener инжектится — все тесты offline на fake openers/responses.
- `default_opener()` построен с no-redirect обработчиком: silent
  redirect запрещён, валидация цели редиректа — отдельный milestone
  SSRF_REDIRECT_AND_SIZE_GATES.

## Тесты (offline, fake openers)

`tests/world_packs/asset_fetch/test_bounded_https.py`:

- позитив: streaming roundtrip, композиция с `fetch_verified`;
- негатив: oversize abort (`SIZE_EXCEEDED`), truncation
  (`SIZE_SHORT`), open/read failures (`OPEN_FAILED`/`READ_FAILED`),
  hard_max tightening, невалидные параметры транспорта, отказ от
  redirect в default opener.

## Запущенные проверки (точный HEAD `f3b6e41b`)

```
python -m pytest tests/world_packs/asset_fetch -q
38 passed
```

Реальных сетевых запросов и загрузок production assets не было.
