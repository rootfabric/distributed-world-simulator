# WP0.9 Shared POI Library — 2026-09-03

Godot: `4.7.1.stable.double.custom_build.a13da4feb`, GL Compatibility, headless.

## Delivered

`scripts/world_packs/poi/poi_library.gd` — the reusable decorative/fixture POI
library required by the roadmap, already consumed by every R1 pack profile:

- builders: `beacon`, `tiny_outpost`, `landing_pad`, `wreck`,
  `research_station_module`, `cave_marker`, `broken_pipeline`;
- every builder is deterministic, asset-free (primitive meshes only) and
  skin-parameterized (`primary`, `secondary`, `accent`, `emissive`,
  `metallic`, `roughness`);
- packs select fixtures via their manifest `poi.catalog` — the pack chooses
  catalog + skin, never authority;
- unknown ids degrade to an empty named node (documented, non-fatal).

## Contract test

`tools/world_packs/poi_library_selftest.gd` +
`RUN_WORLD_PACKS_WP0_9_TESTS.ps1`:

1. every POI id referenced by any pack manifest is supported — PASS
   (7/7 referenced ids);
2. every builder returns a named node with mesh content — PASS
   (7 builders, 24 meshes);
3. skinnability — PASS (custom emissive palette applied to beacon Lamp);
4. unknown-id degradation — PASS;
5. regression: all six registered packs still build — PASS;
6. sentinels: `WORLD_PACKS_POI_LIBRARY_READY`, `WORLD PACKS WP0.9: PASS`.
