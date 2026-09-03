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

- ~~screenshots and draw-call counts require a graphical run~~ — screenshots
  captured 2026-09-04 via the sanctioned MCP path (see below); draw-call
  counters still require a graphics-profiling pass and stay pending.

## MCP graphical capture (2026-09-04)

Managed runtime session through `breakpoint-mcp` (loopback bridges only,
double console binary):

- gallery booted graphically, pads mode captured; live `focus_pack(<id>)`
  switching driven via `runtime_call_method`; one screenshot per pack saved to
  `artifacts/world_packs_mcp/` (gitignored temp evidence):
  `gallery_pads.png`, `focus_wp_moon_industrial.png`, `focus_wp_mars_dust.png`,
  `focus_wp_frozen.png`, `focus_wp_volcanic.png`, `focus_wp_temperate.png`,
  `focus_wp_alien_wetland.png`;
- all six focus sentinels `WORLD_PACKS_GALLERY_FOCUS=<pack>` observed in the
  managed process console output; `runtime_get_tree` confirmed pad nodes.

### Findings and fixes applied the same day

1. Moon star dome was invisible (albedo color multiplied the noise texture to
   black) — replaced by deterministic MultiMesh star points (`WP_Stars`).
2. `Label3D.font_outline_color` does not exist (`outline_modulate` is the
   actual property); the invalid assignment silently killed every label —
   fixed with `outline_modulate` + dark outline for readability on light skies.
3. Volcanic fog density (0.028) swallowed the pad at gallery camera range —
   reduced to 0.01, sun/ambient raised; Frozen 0.02→0.012, Wetland
   0.035→0.022, Temperate sky wash reduced (sky_affect 0.6→0.35).
4. Focus-mode camera moved closer (0,13,20) so a pad fills the frame.
5. Scatter rocks read as "eggs" — y-flattening strengthened and Mars/Volcanic
   scale_max reduced.

Post-fix headless gates all PASS (`WORLD PACKS WP0.10: PASS`), and the
re-capture confirmed labels, stars and per-pack readability.
