# WP1.0 surface-library architecture audit — local implementation evidence

Дата: 2026-09-05. Роль: implementer audit, НЕ independent verification.
Статус: **METADATA CONTRACT CANDIDATE / REVIEW PENDING**.
Ни FOUNDATION DONE, ни GENERATION READY, ни PRODUCTION READY не объявляются.

## LIVE baseline

| Ref / evidence | Проверенное значение |
|---|---|
| main | `5b4152958624be4e9cc40f2369ce32c4964f65c3` |
| WORLD PACKS input | `8da220d50ec0b987c16bd5b5aa4d6d34073a24de` |
| WORLD PACKS input tree | `9183397136f046a25b7b6c6d43e90a33111fdfce` |
| merge-base(main, WP) | `e122d335c9b7bfc1bf8f9e00c47e9efe5bce4293` |
| main -> WP comparison | diverged; 20 ahead / 61 behind |
| WORLDGEN design branch | `cb181b70d6697592777f4830fabd86e3e58f5534`; ancestor of main, not proof of activated runtime |
| WORLD FILL | `002fde20b04e4f8379cdd053ba9b609dfe3b38ef` |
| ECO VIS5 | `a73cccb8064fdfb4df266338d3d20e24ac9f082b`; 365 ahead / 573 behind main |
| Input WP PR lookup | no PR returned for exact head branch, all states |
| Input WP CI | 0 check runs, empty commit statuses; NOT a green CI claim |

Refs были получены GitHub API и повторно проверены перед записью: main и WP не сдвинулись.
Прочитаны root AGENTS/router, main project/harness controls, goals/registry/checkpoints,
WORLDGEN/P7/Dynamic Matter docs, actual material catalog/Moon sampler, WP schema/
validator/profiles/registry/ledger/evidence, WORLD FILL README, ECO VIS5 frame/handoff.
Это targeted architecture audit, не заявление о чтении каждого файла всего репозитория.

## Native Git и publication route

Фактически выполнено:

```text
git --version
# git version 2.47.3

git clone --filter=blob:none --no-checkout https://github.com/rootfabric/distributed-world-simulator.git /mnt/data/dws-native-audit
# fatal: unable to access ... Could not resolve host: github.com
```

Поэтому успешного native checkout нет. `git fetch --all --prune`, `git status`,
`git branch -a`, `git rev-parse`, native `git merge-base` и `git log -n 10` здесь
не выдаются за выполненные над полноценным репозиторием. Live refs/compare получены
через доступный GitHub connector. Обычный Git существует; проблема — сеть окружения.

Сформированы normal Git tree/commit objects через GitHub Git Data API на точной базе,
без force/reset/clean, без перезаписи main и без изменения чужого working tree.
Publication target: новая `feature/world-packs1-surface-library-contract-r1`, PR base:
`feature/world-packs0-content-packs-r1`. Независимый review остаётся отдельным gate.

## Exact implementation subject

```text
commit: d8db747f4e85261b6873160ab20eced989a209e3
tree:   f7562346e58122c4c1b0b863fddfeb244eae260b
parent: 8da220d50ec0b987c16bd5b5aa4d6d34073a24de
```

Локально использован scoped validation workspace, не притворный полный checkout.
Все семь новых implementation files совпали с GitHub commit по Git blob SHA:

| File | Blob SHA |
|---|---|
| `config/world_packs/library_schema.v1.json` | `f4c0403f9d173e34832b62608ad401606d275c27` |
| `config/world_packs/library/catalog.v1.json` | `5a295d8e1c6610cb416eff549d58e2624d6d1d27` |
| `config/world_packs/library/source_locations.v1.json` | `6d00f4ee141426c8f95ac5f8be59a1968947501c` |
| `tools/world_packs/library_contract.py` | `66a81616a04f3acfe7eb6134530d58b3df7300af` |
| `tools/world_packs/requirements-library.txt` | `3ee1ea1a4270a73d0a83859fefca415177450121` |
| `tests/world_packs/test_library_contract.py` | `c3a40a476e9be8c78b94e20faf9a0171ea350d1d` |
| `tests/world_packs/library_fixtures/swatch.txt` | `50b419f0a00bdf8c4c79e9d1c3921cadea21b369` |

Шесть legacy manifests и V1 schema были получены из input commit; локальные copies
проверены по соответствующим upstream blob SHA. Они НЕ входят в изменённые файлы.
Ни `.gd`, ни `.tscn`, ни project settings, ни harness controls не менялись.

## Executed validation

Среда: Linux 6.18.35 x86_64 / glibc 2.41; Python 3.13.5;
jsonschema 4.26.0; pytest 9.0.2. Не Godot/GPU run.

```bash
python -m pytest -q tests/world_packs/test_library_contract.py
# 64 passed in 4.49s

python -m compileall -q tools/world_packs tests/world_packs
# exit 0

python tools/world_packs/library_contract.py --verify-fixtures
# WORLD_PACKS_LIBRARY_CONTRACT: PASS (metadata only)
```

Проверены: strict Draft 2020-12 schema; refs/versions; duplicate IDs/JSON keys;
missing parent/asset/source; cycle; benign diamond; conflicting material/environment;
set-order independence; source relocation without identity change; import/hash change
changes lock; source hash binding; real fixture bytes/size; corruption; unsafe
relative paths/URL syntax; symlinks; unknown/forbidden rights; required attribution;
blank provenance; NaN/Infinity; missing local input diagnostics; six legacy manifests,
legacy unknown-optional acceptance и missing-required rejection.

Три fresh processes c `PYTHONHASHSEED=0`, `17`, `92341` дали одинаковые stdout bytes:

```text
stdout SHA-256:
676ca1f51da341190460c54349c7a6e1140af8d9e97a3ba7c3de61b9b513e5c8

presentation_lock_hash:
bfd0fbb15d8ef5292dd79aa002cb50f11fec9f916531234ee4842a02f52140a4

fixture bytes: 143
fixture SHA-256:
529c893ea8cd6bac13de54f3e1dcc1ba487f98b12c0ee90321f417d8c5e0fb9c
```

Дополнительно выполнена structural проверка roadmap: 11 stages, у каждого все 9
полей Purpose/Why/Inputs/Implementation/Acceptance criteria/Executable proof/
Dependencies/Out of scope/Final gate — PASS. Это не исполнение будущих stage gates.

## Чего evidence НЕ доказывает

Нет реального fetcher, archive extractor, prepared cache, Godot importer/renderer,
capability selection, runtime MaterialCatalog adapter или E2E A–E. Проверка reference
согласованности не является новой исполняемой интеграцией с authoritative Matter.
URL syntax test не доказывает DNS/redirect SSRF protection. Local fixture verification
не доказывает production cache/offline pipeline. License fields не заменяют rights review.
64 metadata tests не закрывают ни planetary runtime, ни performance/10k library gate.

Existing Godot validators найдены и изучены, но в этом аудите НЕ запускались.
Существующий WP0.10 reported build: `4.7.1.stable.double.custom_build.a13da4feb`.
Его исторические PASS и MCP captures сохранены; draw-call profiling остаётся pending.
Никакие тяжёлые внешние payloads, screenshots или engine binaries в Git не добавлены.

## Follow-through

Review этого точного candidate diff, затем WP1.1 safe external-source preparation.
WORLDGEN runtime activation, final independent verification и main promotion требуют
собственных live gates. Не принимать этот implementer report за self-acceptance.
