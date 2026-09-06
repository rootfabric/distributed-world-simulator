# WP-ASSET1 — Consolidated Evidence Summary (EVIDENCE_READY)

- Track: `WP-ASSET1` (WORLD PACKS parallel R1)
- Branch: `work/world-packs-asset1-safe-fetch-r1`
- Risk: MEDIUM
- Final tested implementation HEAD: `1ff25c9a4d6851aac7a957b9feab01e550ebdf6b`
- Все 7 declared milestones завершены.

## Milestone map

| Milestone | Implementation HEAD | Evidence |
|---|---|---|
| FETCH_CONTRACT | `e4baefba2acb26ea6434d6d9e7beed33745ecf30` | `WP-ASSET1_FETCH_CONTRACT_R1.md` |
| BOUNDED_HTTPS | `f3b6e41bb8619ba76b82c2a2121d2ddb7490a574` | `WP-ASSET1_BOUNDED_HTTPS_R1.md` |
| RAW_CONTENT_ADDRESSABLE_CACHE | `cc2c08ebb57e46cc16152230de629d15f58ac059` | `WP-ASSET1_RAW_CACHE_R1.md` |
| SSRF_REDIRECT_AND_SIZE_GATES | `ad7dc25f1319669342a2342eea8bdbf24286a19d` | `WP-ASSET1_GATES_R1.md` |
| ARCHIVE_SAFETY_FIXTURES | `d6fc5350154c0e8e8222526e0416f531cd1198eb` | `WP-ASSET1_ARCHIVE_SAFETY_R1.md` |
| OFFLINE_REUSE_AND_CORRUPTION_RECOVERY | `1ff25c9a4d6851aac7a957b9feab01e550ebdf6b` | `WP-ASSET1_OFFLINE_RECOVERY_R1.md` |
| EVIDENCE_READY | этот документ | — |

## Архитектура поставки

`tools/world_packs/asset_fetch/` — Python stdlib-only пакет:

- `contract.py` — bounded fetch contract (exact id/version/sha256/size
  + approved https source), typed `FetchContractError` /
  `FetchVerificationError`, verified payload или явный typed failure.
- `https.py` — bounded streaming https транспорт (injectable opener,
  hard byte ceiling + probe byte, timeout, no silent redirects).
- `cache.py` — immutable content-addressable raw cache (write-once
  blobs 0444 + O_EXCL + fsync, provenance sidecars, verify-on-read).
- `gates.py` — SSRF/redirect/size gates (userinfo/fragment/port/
  literal-IP отказы, DNS-rebinding защита с injectable resolver,
  bounded redirect chain с ревалидацией каждого hop).
- `archive.py` — archive safety scanner (zip-slip, absolute paths,
  symlinks, zip-bombs: entry/total/count/ratio caps, encrypted
  entries; scan-then-extract).
- `pipeline.py` — cache-first obtain: offline reuse без вызова
  транспорта, quarantine + ровно один recovery refetch при порче.

## Итоговая валидация

На финальном tested implementation HEAD `1ff25c9a`:

```
python -m pytest tests/world_packs/asset_fetch -q
99 passed
```

После tested head — только state/evidence commits (разрешено
протоколом); implementation-файлы не менялись.

## Границы и намеренные ограничения

- Ни одного реального сетевого запроса и ни одной загрузки
  production assets: все транспорты, opener-ы и resolver-ы —
  injected fakes (negative fixtures написаны ДО реальных загрузок,
  как требует work order).
- Кэш живёт вне Git; тяжёлых payloads в репозитории нет.
- Runtime-зависимости отсутствуют (`requirements-asset-fetch.txt`
  декларирует stdlib-only; тесты — pytest).
- Real production asset fetching (реальные CC0 наборы из WP-CONTENT1
  catalog), WORLDGEN adapter и Matter integration — вне scope WP-ASSET1.

## Известный внешний дефект (не WP-ASSET1)

`parallel_controller.py verify/status` сейчас завершается ошибкой
глобально: state-файл `WP-SURFACE1.v1.json` в `origin/work/world-packs-surface1-families-r1`
записан с UTF-8 BOM (PowerShell `>` redirect), и `json.load` контроллера
отказывает на первом символе. Файл вне allowed paths WP-ASSET1;
исправление должно быть выполнено треком WP-SURFACE1 или контроллером
(переписать state без BOM). Собственная state-схема WP-ASSET1 валидна
(проверено `json.load` + формат validation-записей по контроллеру).
