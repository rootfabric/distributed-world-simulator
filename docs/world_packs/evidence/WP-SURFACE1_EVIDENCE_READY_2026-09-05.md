# WP-SURFACE1 — Evidence: EVIDENCE_READY / финальный handoff (2026-09-05)

Track: WP-SURFACE1, branch `work/world-packs-surface1-families-r1`.
Финальный tested head (после R2 review repair): `953e439c17d192b8e0800c1ab791cf31d9883008` (machine-поле `tested_head` в state; первоначальный implementation head `0adbf2aa` остаётся в истории).

## Выполненные milestones

1. FAMILY_TAXONOMY — `282b0f73` — `surfaces/taxonomy.v1.json` (4 семейства, presentation-only).
2. MATTER_BINDING_RULES — `282b0f73` — `surfaces/matter_binding_rules.v1.json`: 6 machine-правил, 5 привязок только к реально существующим Matter ID; sand = PENDING_CANONICAL_MATTER.
3. REGOLITH_BASALT_SAND_ICE_FAMILIES — `1b8946d0` — shard-дескрипторы 4 поверхностей; canonical_material_ids сверяются с binding rules (set equality).
4. FIDELITY_AND_EXPOSURE_STATES — `43776f1f` — `surfaces/state_axes.v1.json` (exposure/fidelity/condition словари per family).
5. RECIPE_FRAGMENT_COMPOSITION — `2df6a710` — `recipes/fragments.v1.json` (5 фрагментов, 2 рецепта, diamond includes) + `environments/airless.v1.json`.
6. CONFLICT_AND_ORDER_INDEPENDENCE_TESTS — `0adbf2aa` — order-independence, конфликтные, циклические и pending-sand негативные proof-ы.
7. EVIDENCE_READY — настоящий файл + state `READY_FOR_INTEGRATION`.

## Matter truth (проверено grep по репо до начала работы)

Реальные ID только из `matter_material_catalog.gd::_default_specs`:
`matter/regolith-loose`, `matter/regolith-compacted`, `matter/basalt`, `matter/fractured-basalt`, `matter/water-ice`, `matter/iron-nickel-ore`, `matter/silicate-waste`.
`matter/sand` НЕ существует → `surface/sand` не имеет привязок (PENDING), попытка привязать любой существующий matter как песок или включить surface/sand в рецепт даёт явный fail.

## Validation (перепрогнано на head 953e439c в рамках R2 review repair, 2026-09-06)

- `python -m pytest tests/world_packs/surface_library -q` → **43 passed** (Windows).
- `python -m pytest tests/world_packs/test_library_contract.py` → Windows: 63 passed, 1 failed (`test_local_missing_symlink_and_corruption`, предсуществующий: `os.symlink` требует SeCreateSymbolicLinkPrivilege, WinError 1314; не связан с WP-SURFACE1). Linux (Ubuntu WSL, ext4): **64/64 passed** на том же head.
- `python -m pytest tests/world_packs/test_parallel_controller.py` → 5 passed.
- Full suite `python3 -m pytest tests/world_packs -q` на Linux (symlink-capable) → **112 passed, 0 failed** на том же head.
- R2 review repair: D1 — все PASS-записи теперь на exact `tested_head` 953e439c; D3 — `compose()` fail-closed на неизвестные Matter ID (тест переписан на `pytest.raises`); D4 — этот раздел перегенерирован. D2 чинится controller repair-веткой, не здесь.

## Изменённые файлы (все в allowed paths WP-SURFACE1)

- `config/world_packs/library/surfaces/{taxonomy,matter_binding_rules,regolith,basalt,sand,ice,state_axes}.v1.json`
- `config/world_packs/library/recipes/fragments.v1.json`
- `config/world_packs/library/environments/airless.v1.json`
- `tests/world_packs/surface_library/{test_surface_families,test_surface_descriptors,test_state_axes,test_recipe_fragments,test_composition_conflicts}.py`
- `docs/world_packs/evidence/WP-SURFACE1_*` (4 файла)
- `config/world_packs/parallel/workstreams/WP-SURFACE1.v1.json`

## Границы

- Matter/strata/physical material не изменялись; WORLD PACKS файлы не выходят за allowed paths; controller-owned файлы не тронуты.
- Не выполнялось (вне scope WP-SURFACE1): WORLDGEN production adapter, Matter mutation integration, WP1.2 final integration, main merge.

## Next

Integrator/Reviewer: child PR `work/world-packs-surface1-families-r1` → `control/world-packs-parallel-r1`, re-review на exact head из machine-поля `tested_head` (953e439c).
