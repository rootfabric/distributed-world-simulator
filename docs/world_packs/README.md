# WORLD PACKS — Data-Driven World Identity Packs

Status: **parallel / noncritical / content-first**  
Branch: `feature/world-packs0-content-packs-r1`

## Why this train exists

The simulator's long-term goal includes many places: different planets, moons, climates, terrains, ecosystems and human/industrial environments. WORLD PACKS gives those places a coherent visual identity without forking the underlying simulation.

A WORLD PACK is data + assets + presentation recipes.

```text
same canonical simulation
          |
          v
     WORLD PACK
   /      |       \
Moon    Mars     Frozen
Industrial Dust   World
```

The pack does not own terrain truth, ECO truth, matter, networking, persistence or authority.

## Pack responsibilities

A pack may define:
- sky/environment profile;
- lighting profile;
- fog/atmosphere presentation;
- ambient audio profile;
- ground/surface material choices;
- decorative prop catalog;
- scatter/dressing recipes;
- decal catalog;
- landmark/POI catalog;
- demo composition presets.

A pack must not define:
- its own terrain generator;
- authoritative weather;
- a new item database;
- network protocol;
- persistence format;
- matter ownership;
- ECO simulation;
- gameplay crafting/economy.

## Key design rule

WORLD PACKS describes **how a world reads**, not **what the world canonically is**.

WORLDGEN may later say "basalt plain, slope 0.12, temperature X". A pack can choose which rock materials, dust decals, sky and props visually represent that descriptor. It cannot rewrite the descriptor.

## Initial pack family

- WP-MOON-INDUSTRIAL
- WP-MARS-DUST
- WP-FROZEN
- WP-VOLCANIC
- WP-TEMPERATE
- WP-ALIEN-WETLAND

The first implementation target is a gallery scene:
`scenes/labs/world_packs/world_packs_gallery.tscn`

## Pack manifest validation (WP0.1)

Pack manifests under `config/world_packs/packs/` are JSON documents validated
against `config/world_packs/pack_schema.v1.json` (draft-07 subset) by
`tools/world_packs/validate_pack.gd`:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_WORLD_PACKS_WP0_1_TESTS.ps1
```

Exit codes: `0` valid, `1` invalid manifest, `2` usage/IO error.
Unknown optional manifest fields are ignored by contract; a pack never carries
canonical state. Promotion gate 1 ("schema validates") is checked with this tool.

See:
- `WORLD_PACKS_ROADMAP.md`
- `AGENT_CONTENT_SCOUT.md`
- `config/world_packs/pack_schema.v1.json`
- `evidence/WP0_1_SCHEMA_VALIDATION_2026-09-03.md`
