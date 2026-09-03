# WP0.10 Pack Gallery + Comparison Harness — 2026-09-04

Godot: `4.7.1.stable.double.custom_build.a13da4feb`, GL Compatibility, headless.

## Delivered

- gallery rewritten as registry-driven (`scripts/world_packs/demo/world_packs_gallery.gd`):
  - pads mode (default): one equally-sized pad (14×14 m) per registered pack
    under a neutral shared environment — identity comparison independent from
    gameplay and per-pack environment settings;
  - focus mode: `-- --pack=<WP-ID>` renders one pack with its full
    environment (sky/lighting/fog) on a single pad;
  - sentinel preserved: `WORLD_PACKS_GALLERY_READY`;
- comparison harness `tools/world_packs/gallery_comparison_harness.gd`:
  captures the WP0.10 record per pack (pack id/version, asset set, surface and
  POI catalogs, renderer, Godot build, node/mesh/MultiMesh counts, object
  budget) and boots the gallery scene headlessly;
- capture record committed:
  `validation/world_packs/wp0_10_gallery_comparison.v1.json` — 6 packs,
  gallery boot: pads=6, nodes=394;
- runner `RUN_WORLD_PACKS_WP0_10_HARNESS.ps1` chains the full promotion-gate
  set: schema validation → license ledger → POI library contract → six-pack
  profile selftest → comparison harness.

## Validation results

- `WORLD_PACKS_VALIDATE: PASS (6 manifest(s))`;
- `WORLD_PACKS_LEDGER: PASS`;
- `WORLD_PACKS_POI_LIBRARY_READY`;
- `WORLD_PACKS_PROFILE: PASS (6 pack(s))`;
- `WORLD_PACKS_GALLERY_HARNESS: PASS (6 pack(s))`, `WORLD_PACKS_GALLERY_HARNESS_READY`;
- `WORLD_PACKS_GALLERY_PACKS=6`, `WORLD_PACKS_GALLERY_READY`.

## Object budget (headless, R1)

| Pack | Mesh instances | MultiMesh instances | Object budget |
|---|---|---|---|
| WP-MOON-INDUSTRIAL | 50 | 90 | 140 |
| WP-MARS-DUST | 39 | 120 | 159 |
| WP-FROZEN | 31 | 70 | 101 |
| WP-VOLCANIC | 29 | 110 | 139 |
| WP-TEMPERATE | 69 | 60 | 129 |
| WP-ALIEN-WETLAND | 48 | 80 | 128 |

## Pending

- screenshots and draw-call counts require a graphical run (MCP runtime
  capture); recorded in the capture record as
  `pending_graphical_mcp_capture`. Headless values above cover node/object
  budgets only.
