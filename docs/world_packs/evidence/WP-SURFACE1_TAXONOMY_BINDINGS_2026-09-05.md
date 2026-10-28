# WP-SURFACE1 — Evidence: FAMILY_TAXONOMY + MATTER_BINDING_RULES (2026-09-05)

Track: WP-SURFACE1, branch `work/world-packs-surface1-families-r1`.
Implementation head: `282b0f734a7a5e79c122c5ac4799c8542c69f42c` (tested_head).

## Что сделано

- `config/world_packs/library/surfaces/taxonomy.v1.json`: семейства `surface-family/regolith`, `surface-family/basalt`, `surface-family/sand`, `surface-family/ice` с physical_anchor, expected_matter_families и binding_status.
- `config/world_packs/library/surfaces/matter_binding_rules.v1.json`: явные правила `BIND_EXISTING_MATTER_ONLY`, `FAIL_ON_UNKNOWN_MATTER_ID`, `FAIL_ON_AMBIGUOUS_BINDING`, `FAIL_ON_FAMILY_MISMATCH`, `PENDING_FAMILY_MUST_NOT_BIND`, `NO_MATTER_MUTATION`; 5 явных привязок только к реально существующим Matter ID; `surface-family/sand` = PENDING_CANONICAL_MATTER (matter/sand в canonical каталоге отсутствует — привязка любых «похожих» matter запрещена как неоднозначная).
- `tests/world_packs/surface_library/test_surface_families.py`: валидатор читает canonical `matter_material_catalog.gd` (read-only, regex-извлечение факт. ID/семейств) и машиной проверяет все правила; негативные тесты подделывают binding-и и требуют fail.

## Matter truth (проверено grep по репо)

Реальные ID из `scripts/simulation/matter/catalog/matter_material_catalog.gd::_default_specs`:
`matter/regolith-loose`, `matter/regolith-compacted` (matter-family/regolith);
`matter/basalt`, `matter/fractured-basalt`, `matter/silicate-waste` (silicate-rock);
`matter/water-ice` (volatile-ice); `matter/iron-nickel-ore` (metallic-ore).
`matter/sand` НЕ существует — поэтому sand = PENDING, без binder-а.

## Validation (на implementation head 282b0f73)

- `python -m pytest tests/world_packs/surface_library/test_surface_families.py -q` → 10 passed.
- `python -m pytest tests/world_packs/test_library_contract.py` → 29 passed, 1 failed: `test_local_missing_symlink_and_corruption` падает на `os.symlink` с WinError 1314 (нет SeCreateSymbolicLinkPrivilege на этой Windows-машине) — предсуществующее окружение, не связано с WP-SURFACE1 (тест использует tmp_path и файлы WP1.0).

## Границы

- Matter/strata/physical material не изменялись (все файлы WP-SURFACE1 — presentation-only metadata + тесты).
- Milestone следующий: REGOLITH_BASALT_SAND_ICE_FAMILIES (sharded surface-дескрипторы).
