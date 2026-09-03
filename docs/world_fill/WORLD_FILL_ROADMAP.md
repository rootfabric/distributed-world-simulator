# WORLD FILL Roadmap

## Train objective

Make canonical simulation outputs legible, atmospheric, memorable and demonstrable without creating a second canon.

## Phase map

### WF0.0 — Train Constitution and Demo Scaffold
**Goal:** freeze the consumer-only boundary and provide one runnable lab scene.

Deliverables:
- branch constitution;
- roadmap;
- plugin/content scout order;
- `world_fill_demo.tscn`;
- clean Godot 4.7.1 import/startup.

Acceptance:
- no new authority owner;
- no new persistent world truth;
- no required wire field;
- demo boots with zero external assets.

### WF0.1 — Environmental Dressing Contract
**Goal:** define a read-only input contract for visual dressing.

Candidate inputs:
- terrain/surface type;
- position / normal / slope;
- altitude;
- moisture / temperature when available;
- ECO opportunity / ground-cover descriptors when available;
- region/biome presentation tags;
- stable seed.

Outputs are presentation-only:
- prop families;
- density bands;
- scale/rotation ranges;
- decal families;
- ambience selectors;
- POI eligibility hints.

Acceptance:
- same inputs + seed => same derived dressing decisions;
- output cannot mutate the source descriptor;
- missing producer fields degrade gracefully.

### WF0.2 — Deterministic Prop Scatter
**Goal:** make large surfaces visually rich using deterministic, removable props.

Initial prop families:
- stones;
- boulders;
- debris;
- dry branches / dead cover;
- crystals;
- industrial scrap.

Baseline implementation should use native `MultiMeshInstance3D`. Editor scatter plugins are optional authoring accelerators, not runtime dependencies.

Acceptance:
- deterministic placement from seed;
- stable LOD/culling budget;
- no network replication per decorative prop;
- no collision unless explicitly required by a later canonical proposal.

### WF0.3 — Surface Scars / Decals
**Goal:** show history already implied by canonical events.

Examples:
- impact dust;
- dig scar;
- exposed material decal;
- construction footprint;
- wheel/contact track;
- rejected-action feedback marker in debug mode.

Acceptance:
- scars are derived from observed events;
- losing a cosmetic scar cannot alter world truth;
- bounded lifetime/budget.

### WF0.4 — Ambient World Clock / Atmosphere
**Goal:** derive a presentation clock and atmosphere from simulation time.

Presentation outputs:
- sun direction;
- sky exposure;
- fog;
- ambient level;
- wind/dust particles;
- ambient loops.

Initial presets:
- clear;
- dust;
- storm;
- dawn;
- night.

Explicit non-goals for WF0:
- movement penalties;
- canonical temperature;
- weather damage;
- sleep rules;
- authoritative storm state.

### WF0.5 — Unified Presentation Event Feedback
**Goal:** one adapter from observed events to feedback.

```text
command/result/event
      |
      v
PresentationEvent
  |      |       |
audio   VFX    camera/UI
```

Initial event set:
- DIG_IMPACT;
- DIG_SUCCESS;
- PICKUP;
- DROP;
- BUILD_COMMIT;
- HANDOFF;
- COMMAND_REJECTED;
- ITEM_TRANSFER.

Acceptance:
- adapter is non-owning;
- unavailable sound/VFX assets never break command execution;
- feedback can be disabled globally.

### WF0.6 — Landmarks / POI Kit
**Goal:** make space navigable and recognizable.

Initial POIs:
- small outpost;
- antenna;
- wreck;
- mining camp;
- research station;
- cave entrance marker;
- landing site;
- radio beacon;
- broken pipeline.

R1 placement may be hand-authored fixtures. Procedural eligibility comes later.

### WF0.7 — Digging Playground Composition
**Goal:** use one integrated place as the visual convergence target.

Composition:
- diggable terrain;
- seam marker;
- starter props;
- lighting;
- rocks/debris;
- one POI;
- ambience;
- signs;
- spectator camera path.

This is a presentation integration lab, not a new digging implementation.

### WF0.8 — Local World Memory
**Goal:** give the player a sense of "I was here" without creating server truth.

R1 storage:
- `user://world_memory/`.

Possible crumbs:
- visited marker;
- local note;
- "dug here" marker;
- observed handoff;
- photo bookmark.

Server persistence is explicitly out of scope until canonically authorized.

### WF0.9 — Labels / Signs / Identity
**Goal:** cheap spatial/social readability.

R1:
- local or fixture-backed labels;
- outpost label;
- container label;
- POI label;
- location name.

Authoritative editable annotations require a separate proposal.

### WF0.10 — Observe / Showcase Toolkit
**Goal:** make demos and visual regressions repeatable.

Capture:
- screenshot;
- simulation tick;
- region;
- authority;
- selected checksum/diagnostics;
- world-fill preset.

Provide spectator bookmarks/splines for:
- spawn;
- outpost;
- dig site;
- seam;
- handoff;
- horizon.

## Global acceptance gates

Every WORLD FILL item must pass all of:
1. **CANON-INDEPENDENT** — removing it cannot change canonical outcome.
2. **NO-NEW-WRITER** — no new authority/persistence owner.
3. **FAIL-SOFT** — missing asset/plugin degrades visually, not functionally.
4. **DETERMINISTIC-WHEN-CLAIMED** — seeded systems prove stable output.
5. **BUDGETED** — explicit object/triangle/draw-call/audio budgets where relevant.
6. **DEMO-VISIBLE** — feature can be observed in a dedicated lab or Digging Playground.
7. **LICENSE-CLEAN** — imported third-party content has a ledger entry.

## Stop conditions

Stop WORLD FILL implementation and open a canonical proposal if a task asks for:
- authoritative durability/charge;
- crafting consumption/output;
- weather gameplay effects;
- NPC inventory ownership;
- networked editable signs;
- persistent server-side memories;
- gameplay collision/physics truth for decorative props;
- new wire schema required for correctness.
