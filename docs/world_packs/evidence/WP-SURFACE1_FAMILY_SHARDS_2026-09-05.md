# WP-SURFACE1 — Evidence: REGOLITH_BASALT_SAND_ICE_FAMILIES (2026-09-05)

Track: WP-SURFACE1, branch `work/world-packs-surface1-families-r1`.
Implementation head: `1b8946d0a9747258c3162047a98a97e12f6c1df0` (tested_head).

## Что сделано

Sharded surface-дескрипторы (`dws.world_packs.surface_descriptor.v1`):

- `config/world_packs/library/surfaces/regolith.v1.json` → `surface/regolith`, BOUND: `matter/regolith-loose`, `matter/regolith-compacted`.
- `config/world_packs/library/surfaces/basalt.v1.json` → `surface/basalt`, BOUND: `matter/basalt`, `matter/fractured-basalt`.
- `config/world_packs/library/surfaces/sand.v1.json` → `surface/sand`, PENDING_CANONICAL_MATTER: `canonical_material_ids: []`; привязка matter/silicate-waste или matter/regolith-loose как песка запрещена (неоднозначная физическая привязка).
- `config/world_packs/library/surfaces/ice.v1.json` → `surface/ice`, BOUND: `matter/water-ice`.

`canonical_material_ids` каждого дескриптора машино-сверяются с `matter_binding_rules.v1.json` (set equality), `binding_status` — с таксономией; дескриптор не может объявить matter, отсутствующий в canonical каталоге (тест читает `matter_material_catalog.gd`).

- `tests/world_packs/surface_library/test_surface_descriptors.py`: 8 тестов (4 live-инварианта + 4 негативных).

## Validation (на implementation head 1b8946d0)

- `python -m pytest tests/world_packs/surface_library -q` → 18 passed (10 taxonomy/bindings + 8 descriptors).

## Границы

- Изменены только allowed paths WP-SURFACE1. Matter/strata/physical material не тронуты.
- Следующий milestone: FIDELITY_AND_EXPOSURE_STATES (оси exposure/fidelity для всех четырёх семейств).
