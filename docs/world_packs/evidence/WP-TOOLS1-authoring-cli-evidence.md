# WP-TOOLS1 — Authoring CLI + Doctor + Index/Search + Scale Fixtures Evidence

Track: `WP-TOOLS1` · Branch: `work/world-packs-tools1-authoring-cli-r1`
Resolver contract reused: `tools/world_packs/library_contract.py` (WP1.0, `wp-set-json-v1`). Второго resolver-а нет: CLI импортирует контракт-модуль, и тесты доказывают побайтовое совпадение lock-вывода CLI с прямым вызовом `library_contract.resolve`.

## Milestones

### CLI_SCAFFOLD — `bc161e0a`
`tools/world_packs/wp_cli/` (argparse-диспетчер, контракт 0/1/2 exit codes, `validate`), `RUN_WORLD_PACKS_TOOLING_TESTS.ps1/.sh`. Тесты: 6 passed.

### VALIDATE_AND_RESOLVE — `792ef7ed`
`resolve` печатает WP1.0 presentation lock. Известный hash `bfd0fbb15d8ef5292dd79aa002cb50f11fec9f916531234ee4842a02f52140a4` совпадает с прямым вызовом контракта. Тесты: 11 passed.

### DOCTOR_DIAGNOSTICS — `24e459c7`
`doctor`: python_runtime (>=3.11), jsonschema, library_schema, catalog/locations documents, contract_validate, repo_fixture_bytes (size+sha256), default_recipe_resolve, legacy_pack_manifests; `--json`, точечные FAIL/SKIP. Тесты: 16 passed.

### INSPECT_AND_INDEX — `214fcd2d`
`index` — детерминированный полный индекс `id@version -> digest` + `index_digest`; `inspect REF...` — group/digest/descriptor, строгий отказ на неизвестные ссылки. Тесты: 22 passed.

### SYNTHETIC_1K_SCALE / SYNTHETIC_10K_SCALE
`wp scale-fixture --count N --seed S --out DIR`: генерирует metadata-only descriptors (assets/surfaces/recipes/environments + locations), ровно N дескрипторов, recipes ≤ 128 (schema maxItems). Никаких payload-байтов: synthetic sources — `https://assets.example.org/synthetic/...`, контракт проверяет их только синтаксически, offline. Измеряет read/validate/resolve существующим resolver-ом.

Измерения (seed 7, Windows, Python 3.11.8, jsonschema 4.22.0):

| count | assets | surfaces | recipes | read, s | validate, s | resolve, s | lock (первые 16) |
|-------|--------|----------|---------|---------|-------------|------------|------------------|
| 1 000 | 596 | 398 | 5 | 0.0194 | 0.3288 | 0.0454 | `1ad05bb6ccc37266` |
| 10 000 | 5969 | 3980 | 50 | 0.0819 | 3.1159 | 0.5155 | `c947790a3066a3de` |

Raw отчёты: `artifacts/world_packs_parallel/wp-tools1-scale-1k.json`, `wp-tools1-scale-10k.json` (generated cache, не durable truth).

Наблюдение: validate растёт ~линейно с супер-линейным jsonschema-оверхедом (≈0.33 s → ≈3.1 s при ×10), resolve остаётся дешёвым (<0.6 s на 10k) благодаря set-based композиции. Блокеров масштаба до 10k нет.

Determinism proof: одинаковый (count, seed) даёт побайтово идентичные документы и одинаковый lock hash (тест `test_generated_documents_are_deterministic`).

## Validation commands (точные HEAD — в state JSON)

- `./RUN_WORLD_PACKS_TOOLING_TESTS.ps1` → PASS (см. state)
- `python -m pytest tests/world_packs/wp_cli tests/world_packs/scale_fixtures -q`

## Known environment note

`tests/world_packs/test_library_contract.py::test_local_missing_symlink_and_corruption` требует `os.symlink` (WinError 1314 без developer mode/admin на этом Windows-раннере). Файл не принадлежит WP-TOOLS1 и не менялся; тест деселектирован в Windows run-script с указанием причины.
