# WP1.2 Prepared Asset + Offline Lock — Evidence (R2-H)

Milestone: **WP1.2 Prepared Assets + Offline Lock** на integration-ветке
`integration/world-packs-wp1-2-foundation-r1`.

## Выбранный candidate

**ambientCG Ice001, 1K JPG-вариант** (из WP-CONTENT1 `candidate/ambientcg/ice001`):
- License: **CC0-1.0** (https://docs.ambientcg.com/license/, page_license_statement,
  перепроверено 2026-09-06), preview+assets;
- 1K (не 4K/8K), один маленький реальный архив: **5 770 801 байт**;
- **реальный SHA-256**: `721e7fc523524a7f09a90518be17205a2f4f8f99a48e481821e1b6c482ecdf25`
  (измерен фактической загрузкой; никакие значения не выдуманы);
- source: `https://ambientcg.com/get?file=Ice001_1K-JPG.zip` (302 →
  `acg-download.struffelproductions.com/...`); оба хоста в approved_hosts рецепта.

## Реализация

- `config/world_packs/prepared/recipes/ambientcg-ice001-1k.v1.json` — версионируемый import
  recipe (schema `dws.world_packs.prepared_import_recipe.v1`): identity = recipe_id@version +
  raw sha256; URL переносимы и не являются identity; member_allow = Color/NormalGL/Roughness/
  Displacement (Godot = GL-нормали; DX отвергнут); import-настройки (sRGB-флаги, mipmap, filter,
  roughness channel, importer_version) фиксированы в рецепте.
- `tools/world_packs/prepared/wp_prepare.py` — load_recipe (typed validation), acquire через
  **asset_fetch.obtain_safe** (единственный безопасный entrypoint: approved hosts, DNS-pinning,
  redirect-revalidation, size/hash gates, immutable raw cache), extract (scan-then-extract,
  fail-closed), prepared_identity = raw hash + recipe version + Godot version + **SHA-256 Godot
  binary** + renderer + platform + import settings, prepare (bundle + manifest), verify_prepared
  (offline size/hash verify).
- `tools/world_packs/prepared/proof_e.py` — Proof E.
- `scripts/world_packs/prepared/prepared_sample_self_check.gd` — offline sample boot: Godot
  `4.7.1.stable.double.custom_build.a13da4feb` headless читает manifest и декодирует каждую
  карту (JPG) без import-сервера и без сети.

## Proof E — результат (2026-09-06): PASS 14/14

| # | Случай | Результат |
|---|--------|-----------|
| E1 | пустые raw/prepared кэши → acquire через obtain_safe | PASS |
| E2 | verify bytes/hash → safe extraction | PASS |
| E3 | prepare (prepared bundle по identity) | PASS |
| E4 | offline verify prepared | PASS |
| E5 | sample boots (Godot headless, карты декодируются) | PASS |
| F1 | offline: raw cache reuse | PASS |
| F2 | offline: prepared cache reuse | PASS |
| F3 | offline sample: NO HTTP/DNS | PASS |
| F4 | offline acquire denied (zero network) | PASS |
| N1 | corrupt raw cache → quarantine + refetch recovery | PASS |
| N2 | corrupt prepared cache → typed PREPARED_CORRUPT | PASS |
| N3 | hash mismatch recipe → отказ | PASS |
| N4 | old lock after library update → identity invalidation | PASS |
| N5 | mirror relocation (URL swap) → identity/cache reuse | PASS |

Прогон: `python tools/world_packs/prepared/proof_e.py --work-dir <tmp>` — «PROOF_E: PASS (14/14)».
Работа Proof E велась с прямым (direct) сетевым выходом; pinning-transport конструктивно
отказывается от proxy CONNECT-туннелей (fail-closed).

## Regression

После WP1.2-изменений: Windows full `tests/world_packs` — 325 passed + 1 environmental
symlink FAIL (WinError 1314, не deselect, не зелёный); asset_fetch focused — 127 passed;
compileall clean. Linux (Ubuntu WSL) full suite на финальном HEAD — см.
WP1_2_FOUNDATION_EVIDENCE (записан ниже в этом файле при финализации).

## Границы

- Prepared/raw кэши живут вне репозитория; в Git не добавлено ни одного бинарного payload.
- Никакого canonical terrain/Material authority, WORLDGEN adapter, main merge — не выполнялось.
