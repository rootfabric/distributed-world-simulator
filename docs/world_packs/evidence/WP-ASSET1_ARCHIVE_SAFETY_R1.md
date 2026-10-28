# WP-ASSET1 — Evidence: ARCHIVE_SAFETY_FIXTURES

- Track: `WP-ASSET1`
- Branch: `work/world-packs-asset1-safe-fetch-r1`
- Implementation HEAD: `d6fc5350154c0e8e8222526e0416f531cd1198eb`
- Milestone: `ARCHIVE_SAFETY_FIXTURES`
- Дата (UTC): 2026-09-05

## Что реализовано

`tools/world_packs/asset_fetch/archive.py` (stdlib-only `zipfile`,
`posixpath`, `ipaddress`-free):

- `scan_zip`: полная проверка всех записей ДО распаковки —
  относительные нормализованные имена без выхода за корень
  (`PATH_TRAVERSAL`, `ABSOLUTE_ENTRY_PATH`, включая Windows-формы,
  `BACKSLASH_ENTRY_NAME`, `NUL_IN_ENTRY_NAME`, `EMPTY_ENTRY_NAME`);
  запрет encrypted entries (`ENCRYPTED_ENTRY`); запрет symlink-членов
  по unix-режиму в external_attr (`LINK_ENTRY`); лимиты: per-entry
  size (`ENTRY_TOO_LARGE`), total uncompressed
  (`TOTAL_TOO_LARGE`), entry count (`TOO_MANY_ENTRIES`), declared
  compression ratio (`COMPRESSION_BOMB`); невалидный zip →
  `NOT_A_ZIP`.
- `extract_zip_safe`: scan-then-extract с повторной проверкой
  каждого имени и resolve()-проверкой destination внутри корня;
  потоковая запись с per-entry byte cap и при извлечении.

## Negative fixtures (offline, in-memory + tmp_path)

`tests/world_packs/asset_fetch/test_archive_safety.py` (18 тестов):
zip-slip (`../`, `a/../..`), absolute/unix+windows пути, `~`, NUL,
backslash-имена (через прямой валидатор — zipfile нормализует
backslash на Windows), symlink-член, compression bomb (10 MB нулей),
per-entry/total/count caps (несжимаемые random payloads), encrypted
entry (флаг поднят патчем central directory), refusal при извлечении
не оставляет файлов вне корня.

## Запущенные проверки (точный HEAD `d6fc5350`)

```
python -m pytest tests/world_packs/asset_fetch -q
93 passed
```
