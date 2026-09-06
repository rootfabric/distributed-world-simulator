# WP1.2 Foundation Integration — Composition & Composed Regression Evidence (R2-F/R2-G)

Integration branch: `integration/world-packs-wp1-2-foundation-r1`
Base: `control/world-packs-parallel-r1@2120e51a355a9e5b18f71449de59ab13b9cbbde3` (controller R2 repair merged after PASS review)

## Authorization (R2-E)

`WP1_2_FOUNDATION_INTEGRATION = AUTHORIZED` по контроллеру: все 5 треков READY_FOR_INTEGRATION
с PASS-validation ровно на tested_head и review PASS (machine-поля), WP1_0_INDEPENDENT_REVIEW = PASS
(PR #553, финальный чистый прогон Linux 64/64), critical main drift NONE, execution base drift NONE,
cross-track overlap NONE.

## Composition (порядок по кампании; все merge --no-ff, без rebase, без конфликтов)

| # | Merge | HEAD после | Focused tests |
|---|-------|-----------|---------------|
| 1 | WP-SURFACE1 (review PASS @ f42c8731) | f290d8f0 | surface_library + parallel_controller: 57 passed |
| 2 | WP-CONTENT1 (review PASS @ 3c11db73) | f126634a | content_catalog: 19 passed |
| 3 | WP-ASSET1 (security review PASS @ f85b2cd4) | 5845fbcc | asset_fetch: 127 passed |
| 4 | WP-TOOLS1 (review PASS @ bd6dbfaf) | 204fdf45 | wp_cli + scale_fixtures: 28 passed |
| 5 | WP-VIS1 (review PASS @ 02b07774) | **8cd99c28** (final) | material_lab: 31 passed |

## Composed regression (R2-G), финальный HEAD 8cd99c28e5bb2bcd32b68348ae95bcc8630fe40b

- `python -m pytest -q tests/world_packs` (Windows): **325 passed, 1 failed** — единственный fail
  `test_local_missing_symlink_and_corruption`, OSError WinError 1314 (нет symlink-привилегии;
  предсуществующее окружение, НЕ засчитано зелёным, не deselect).
- `python -m pytest -q tests/world_packs` (Ubuntu WSL, ext4, symlink-capable, тот же HEAD):
  **326 passed, 0 failed** — полный чистый прогон без исключений.
- `python tools/world_packs/parallel_controller.py status|next`: CONTROLLER@2120e51a,
  MAIN_MOVEMENT=NONE, CRITICAL_MAIN_DRIFT=NONE, WORKSTREAM_OVERLAPS=NONE, все треки READY/OK;
  `WP1_2_FOUNDATION_INTEGRATION = READY`.
- Godot `4.7.1.stable.double.custom_build.a13da4feb`:
  - headless `surface_material_lab_self_check.gd`: **PASS surfaces=7 markers=0** (exit 0);
  - один graphical smoke `surface_material_lab_capture.gd`: **PASS** (exit 0), оба PNG
    (174648 / 106849 байт) совпадают по размеру с зафиксированными evidence-артефактами WP-VIS1.
- Legacy WP0 (Godot headless, тот же HEAD):
  - `validate_pack.gd --dir=res://config/world_packs/packs`: **PASS (6 manifest(s))**;
  - `pack_profile_selftest.gd -- --all`: **PASS (6 pack(s))**;
  - `poi_library_selftest.gd`: **PASS (7 builders, 24 meshes, 7 referenced ids)**;
  - `gallery_comparison_harness.gd`: **PASS (6 pack(s) captured)**;
  - `check_asset_ledger.gd`: **PASS**.

## Границы

Никаких merge в main, force-push, rebase или history rewrite не выполнялось. Worker-ветки не
rebase-ились. Все композиции — обычные non-destructive merges reviewed heads.
