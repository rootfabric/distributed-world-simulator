# WP-ASSET1 — R2 Security Review Repair Map (PR #560)

Independent R2 security review @ e7ac3e0a6f3151c02863de9d335ca9c1c8ccf0e2: **FAIL** — ни один из четырёх обязательных security-fix не реализован. Worker-набор зелёный (99 passed), потому что ни один из четырёх security-кейсов им не покрывается. Этот документ — обязательный Repair Map для MEDIUM-risk трека (R2-D).

## FIX 1 — DNS rebinding / TOCTOU

- **Root cause:** `gates.validate_target` валидирует hostname через `check_resolved_addresses` (gates.py:113-114), но `https.make_bounded_transport` открывает `contract.url` обычным urllib-opener'ом (https.py:78): urllib заново резолвит hostname в момент connect. Валидированный endpoint ≠ фактическому подключённому endpoint.
- **Affected files:** `tools/world_packs/asset_fetch/https.py`, `tools/world_packs/asset_fetch/gates.py`.
- **Entry points:** `make_bounded_transport`, `default_opener`, (новый) `make_pinned_bounded_transport`, `PinnedHTTPSConnection`.
- **Callers:** pipeline (`obtain`/`obtain_safe`), WP1.2 prepared-asset flow (будущий consumer).
- **Sibling paths:** redirect-хопы — каждый hop получает свой pinned transport.
- **Missing tests:** adversarial first-answer-public / second-answer-private; проверка фактического адреса connect.
- **Selected fix:** разрешить hostname ОДИН раз (`resolver(host)`), проверить ВСЕ ответы публичностью (re-use `check_resolved_addresses`), выбрать первый публичный IP и подключаться напрямую к нему через `http.client.HTTPSConnection`-подкласс с переопределённым `connect()`: сокет создаётся к pinned IP, а `ssl_context.wrap_socket(sock, server_hostname=original_host)` сохраняет SNI, Host-header (из URL) и проверку сертификата по оригинальному hostname. Повторного DNS-резолва не происходит вообще.
- **Why this closes the defect:** соединение физически не может уйти на адрес, отличный от проверенного: connect идёт к literal IP, а не hostname; TLS-верификация остаётся по hostname (нет downgrade).
- **Validation plan:** unit-тест с fake resolver: первый вызов → public IP (gate PASS), второй вызов (в transport) → 127.0.0.1 ⇒ `GateError PRIVATE_ADDRESS_TARGET`, `opener.open` не вызывается; тест `PinnedHTTPSConnection.connect` с записывающим `socket.create_connection`-shim: адрес сокета == pinned IP, `server_hostname` == оригинальный hostname.

## FIX 2 — единственный безопасный production entrypoint

- **Root cause:** `pipeline.obtain(contract, cache, transport)` принимает произвольный transport-callback (pipeline.py:44-47); gates не выполняются. Демонстрация ревьюера: `obtain(evil_contract, cache, lambda c: b"EVIL")` прошёл без единого gate.
- **Affected files:** `tools/world_packs/asset_fetch/pipeline.py`, `__init__.py`.
- **Entry points:** новый `obtain_safe(...)` (+ alias `prepare_raw_asset`); существующий `obtain` помечен как `unsafe_low_level` (documented).
- **Callers:** WP1.2 prepared-asset milestone, CLI/скрипты.
- **Sibling paths:** cache reuse (`cache.has`) остаётся до gates — offline reuse не требует сети и не обходит верификацию контракта: `obtain_safe` сначала строит/валидирует контракт, затем идёт в cache-first поток.
- **Missing tests:** public API не доходит до transport при провале target-validation (transport-spy: 0 вызовов).
- **Selected fix:** `obtain_safe` всегда выполняет цепочку `contract_from_dict → validate_target (approved hosts + resolver + size ceiling) → resolve_redirect_chain (каждый hop revalidated) → make_pinned_bounded_transport → verify_payload → cache.put_verified`, с corruption-recovery из `obtain`.
- **Why this closes the defect:** единственная композиция, доступная production-коду, структурно не может пропустить ни один gate; обходной путь требует осознанного использования задокументированного unsafe-примитива.
- **Validation plan:** spy-transport тесты (unapproved host, private resolution, non-https, oversized declared size) + позитивный путь через fake pinned opener.

## FIX 3 — typed errors для malformed URL

- **Root cause:** `urlsplit(url).port` бросает сырой `ValueError` (`Port could not be cast...`, `Port out of range...`). В `gates.validate_target` (gates.py:103) не перехвачен; в `contract.contract_from_dict` (contract.py:148-156) `.port` вообще не читается — malformed URL принимается как валидный контракт.
- **Affected files:** `gates.py`, `contract.py`.
- **Missing tests:** `https://example.org:bad/file`, `https://example.org:99999/file` на обоих слоях.
- **Selected fix:** безопасное чтение порта через helper, обе аномалии → typed `GateError("MALFORMED_URL"|"FORBIDDEN_PORT")` / `FetchContractError("INVALID_SOURCE_URL"|"FORBIDDEN_PORT")`.
- **Why this closes the defect:** fail-closed на malformed источнике до любого fetch; нет необработанных Python-исключений наружу API.
- **Validation plan:** негативные тесты обоих URL на обоих слоях; полный suite.

## FIX 4 — archive collision / special-file policy

- **Root cause:** `archive.scan_zip` (a) не проверяет case-insensitive коллизии (`A.txt`+`a.txt` — ревьюер воспроизвёл silent overwrite на extraction), (b) не проверяет дубликаты нормализованных путей (`foo/bar` vs `foo//bar` vs `foo/./bar`), (c) из non-regular Unix-режимов в `external_attr` отвергает только S_IFLNK (archive.py:105-110): FIFO/socket/chardev/blockdev проходят. Tar-путь отсутствует.
- **Affected files:** `tools/world_packs/asset_fetch/archive.py`.
- **Entry points:** `scan_zip`/`extract_zip_safe`, новые `scan_tar`/`extract_tar_safe`.
- **Missing tests:** перечисленные коллизии и special-file fixtures (zip и tar).
- **Selected fix:** single-pass пред-extraction проверка: множество seen-нормализованных имён + casefold-множество при `case_insensitive_targets=True` (default), отказ при любом дубликате (`DUPLICATE_ENTRY_PATH` / `CASE_INSENSITIVE_COLLISION`); file-type из `external_attr >> 16 & 0o170000` — разрешены только `0` и `S_IFREG`, иначе `NON_REGULAR_ENTRY` (symlink остаётся `LINK_ENTRY`); tar: тот же контракт через `tarinfo` (`isreg()`-only).
- **Why this closes the defect:** все отказы происходят ДО extraction, silent overwrite невозможен ни на одном OS/FS.
- **Validation plan:** adversarial fixtures ревьюера (A.txt/a.txt overwrite, FIFO/socket/chr/blk zip, dup-normalized zip) должны давать typed refusal до записи; tar-эквиваленты; полный suite + Linux full regression.

## Порядок и границы

Все изменения строго внутри allowed paths WP-ASSET1: `tools/world_packs/asset_fetch/**`, `tests/world_packs/asset_fetch/**`, `docs/world_packs/evidence/WP-ASSET1*`, state-файл. После реализации: `python -m pytest -q tests/world_packs/asset_fetch`, независимый adversarial re-verify, полный regression (Windows + Linux/WSL), state `tested_head` = implementation head с PASS-записями ровно на нём, normal push, re-review.
