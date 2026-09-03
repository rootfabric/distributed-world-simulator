# WORLD PACKS Roadmap

## Status (2026-09-04)

| Milestone | Status | Evidence |
|---|---|---|
| WP0.0 Constitution + Gallery | done | `evidence/WP0_0_GODOT_VALIDATION_2026-09-03.md` |
| WP0.1 Pack Contract / Schema | done | `evidence/WP0_1_SCHEMA_VALIDATION_2026-09-03.md` |
| WP0.2 Content License Ledger | done (enforced-empty) | `evidence/WP0_2_LICENSE_LEDGER_2026-09-03.md` |
| WP0.3 Moon Industrial R1 | done | `evidence/WP0_3_MOON_INDUSTRIAL_2026-09-03.md` |
| WP0.4 Mars Dust R1 | done | `evidence/WP0_4_MARS_DUST_2026-09-03.md` |
| WP0.5 Frozen World R1 | done | `evidence/WP0_5_FROZEN_2026-09-03.md` |
| WP0.6 Volcanic World R1 | done | `evidence/WP0_6_VOLCANIC_2026-09-03.md` |
| WP0.7 Temperate R1 | done | `evidence/WP0_7_TEMPERATE_2026-09-03.md` |
| WP0.8 Alien Wetland R1 | done | `evidence/WP0_8_ALIEN_WETLAND_2026-09-03.md` |
| WP0.9 Shared POI Library | done | `evidence/WP0_9_POI_LIBRARY_2026-09-03.md` |
| WP0.10 Gallery + Comparison Harness | done | `evidence/WP0_10_GALLERY_HARNESS_2026-09-04.md` |

All R1 packs are asset-free procedural presentations; screenshots and
draw-call capture remain a pending graphical (MCP) run recorded in the WP0.10
capture record. External CC0 content integration proceeds through the WP0.2
ledger and the content-scout work orders.

## WP0.0 — Pack Constitution + Gallery Scaffold
Freeze scope and provide a runnable asset-free gallery.

Acceptance:
- no canonical owner;
- no mandatory network/persistence changes;
- gallery starts without third-party assets.

## WP0.1 — Pack Contract / Schema
Define versioned data for:
- identity;
- environment;
- materials;
- prop catalogs;
- scatter recipes;
- decals;
- POIs;
- ambience;
- compatibility requirements.

The schema must allow unknown optional fields to be ignored.

## WP0.2 — Content License Ledger
Every third-party asset requires provenance and redistribution status.

For each source record:
- source URL;
- creator/source;
- asset/pack name;
- download date;
- license + license URL;
- redistribution permission;
- modifications;
- checksum;
- files imported.

No ambiguous asset is committed to the public repository.

## WP0.3 — Moon Industrial R1
Purpose: first flagship pack for the digging/outpost experience.

Visual vocabulary:
- grey basalt/regolith;
- hard sunlight;
- deep dark sky;
- industrial beacon;
- crates/scrap;
- antennas/pipes;
- sparse rocks;
- dust scars.

R1 is presentation-only.

## WP0.4 — Mars Dust R1
Vocabulary:
- red/orange dust;
- layered rock;
- haze;
- worn industrial props;
- dust decals;
- low-contrast horizon.

## WP0.5 — Frozen World R1
Vocabulary:
- ice/snow surfaces;
- cold blue ambient response;
- exposed rock;
- frost/ice props;
- low drifting particles.

## WP0.6 — Volcanic World R1
Vocabulary:
- dark igneous rock;
- emissive cracks/lava-like presentation;
- ash haze;
- basalt formations.

No canonical heat/damage in WORLD PACKS.

## WP0.7 — Temperate R1
Vocabulary:
- soil/rock/grass materials;
- wet/dry variants;
- simple vegetation dressing;
- softer sky.

ECO remains owner of ecological truth.

## WP0.8 — Alien Wetland R1
Vocabulary:
- wet ground;
- shallow-water presentation;
- unusual ground cover;
- fog;
- non-Earth color/material composition.

No new liquid simulation is authorized by this pack.

## WP0.9 — Shared POI Library
Create reusable decorative/fixture POIs:
- beacon;
- tiny outpost;
- landing pad;
- wreck;
- research station module;
- cave marker;
- broken pipeline.

Pack selects skin/material/catalog, not authority.

## WP0.10 — Pack Gallery + Comparison Harness
One scene must show multiple packs using equivalent geometry so reviewers can compare identity independently from gameplay.

Capture:
- pack id/version;
- asset set;
- renderer;
- Godot build;
- screenshot;
- draw calls / object counts.

## Promotion gates

A pack is demo-ready when:
1. schema validates;
2. source/license ledger is complete;
3. no missing resources;
4. fresh Godot import passes;
5. gallery scene boots;
6. pack can be disabled with canonical behavior unchanged;
7. asset budget is documented.

## Relationship with WORLD FILL

WORLD PACKS supplies content/profile choices.
WORLD FILL supplies generic mechanisms that consume them.

```text
WORLD PACKS
  data/assets
      |
      v
WORLD FILL mechanisms
      |
      v
rendered world
```

Neither train may become a prerequisite for P7, WORLDGEN, ECO, FABRIC, NETWORK or persistence.
