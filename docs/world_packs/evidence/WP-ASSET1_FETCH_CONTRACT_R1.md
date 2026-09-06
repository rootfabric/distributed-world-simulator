# WP-ASSET1 — Evidence: FETCH_CONTRACT

- Track: `WP-ASSET1`
- Branch: `work/world-packs-asset1-safe-fetch-r1`
- Implementation HEAD: `e4baefba2acb26ea6434d6d9e7beed33745ecf30`
- Milestone: `FETCH_CONTRACT`
- Дата (UTC): 2026-09-05

## Что реализовано

`tools/world_packs/asset_fetch/contract.py` — bounded fetch contract:

- `contract_from_dict`: строгая валидация exact asset id / version / sha256
  (64 lowercase hex, нормализация верхнего регистра) / expected size
  (положительный, ограничен `DEFAULT_MAX_ASSET_BYTES` = 64 MiB) / approved
  source (только https, host из явно переданного непустого approved set).
- Типизированные ошибки: `FetchContractError` / `FetchVerificationError`
  со стабильными machine-readable кодами (`INVALID_ASSET_ID`,
  `INVALID_SHA256`, `INVALID_EXPECTED_SIZE`, `EXPECTED_SIZE_ABOVE_CEILING`,
  `NON_HTTPS_SOURCE`, `UNAPPROVED_SOURCE_HOST`, `NO_APPROVED_HOSTS`,
  `SIZE_MISMATCH`, `HASH_MISMATCH`, `PAYLOAD_NOT_BYTES`,
  `TRANSPORT_ERROR`, ...).
- `verify_payload` / `fetch_verified`: verified payload (опционально
  temporary file) только при полном совпадении size+sha256; иначе typed
  failure. Транспорт инжектится — сетевое чтение отсутствует на этом
  milestone.
- Пакет stdlib-only (см. `tools/world_packs/requirements-asset-fetch.txt`).

## Negative fixtures (до любых реальных загрузок)

`tests/world_packs/asset_fetch/test_fetch_contract.py`: 17
параметризованных invalid-field кейсов, missing keys, пустой
approved-host set (fail-closed), non-mapping contract, tampered payload
(hash mismatch), size mismatch, non-bytes payload, transport error,
tampered injected transport. Позитивные кейсы: валидный контракт,
нормализация hash, temp-file roundtrip с dispose.

## Запущенные проверки (точный HEAD `e4baefba`)

```
python -m pytest tests/world_packs/asset_fetch -q
29 passed
```

Сетевых запросов нет; все транспорты — injected fakes. Тяжёлые
production assets не скачивались.
