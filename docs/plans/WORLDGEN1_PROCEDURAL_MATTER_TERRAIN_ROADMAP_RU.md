# WORLDGEN1 — Procedural Matter Terrain

**Status:** PLANNED / DESIGN-ONLY UNTIL ACTIVATION GATE  
**Date:** 2026-09-03  
**Canonical design base:** `main @ aca907022bf3a3239ae53ae0583c6aff8004da98`  
**Program class:** future research / world-generation lane  
**Current product blocker:** none  
**Execution authorization:** NOT YET GRANTED

## 1. Purpose

WORLDGEN1 turns the already existing Matter generation + materialization + mutation stack into a general procedural planetary terrain foundation capable of producing substantially more complex natural geometry than the current near-spherical surface.

The target is not a second terrain system.

```text
WORLDGEN1 = PROCEDURAL REVISION-0 MATTER GENERATION
P7/MW4   = RUNTIME CANONICAL MATTER MUTATION

BOTH MUST FEED THE SAME MATTER REPRESENTATION AND MESHING PATH.
```

The long-term product goal is to generate different planets and locations with different:

- macro planetary shapes;
- mountain systems and ridges;
- hills and basins;
- ravines and canyons;
- cliffs and overhangs;
- craters;
- caves, chambers and tunnels;
- lava tubes;
- geological strata and material composition;
- soil/regolith depth;
- biome-relevant terrain fields;
- ruins, settlements and buildings through Construction rather than terrain-owned structure truth.

## 2. Why the current architecture is unusually well suited

The existing Matter stack already contains the key seam needed for this.

### 2.1 Procedural revision 0 already exists

`scripts/simulation/matter/storage/matter_brick_materializer.gd` materializes a missing brick by sampling a procedural sampler over the brick grid.

Conceptually:

```text
cell address
    ↓
MatterBrickMaterializer
    ↓
procedural sampler(position)
    ↓
Matter samples
    ↓
MatterBrickSnapshot revision 0
```

A planet therefore does not need every high-resolution brick stored eagerly.

### 2.2 The Moon sampler is already signed-distance based

`scripts/simulation/matter/generation/moon_geology_sampler.gd` currently derives the surface from approximately:

```text
signed_distance =
    |body_fixed_position|
    - canonical_surface_radius
```

This naturally produces a near-spherical, smooth base.

That is not a limitation of Matter. It is only the current sampler definition.

The sampler can evolve from:

```text
sphere SDF
```

to:

```text
base planet
+ macro relief
+ local surface features
- caves
- canyons
+ ridges
+ crater rims
+ geological/material fields
```

while keeping the downstream Matter and mutation contracts unchanged.

### 2.3 FeatureCatalog is already a natural extension point

`scripts/simulation/matter/generation/moon_surface_feature_catalog.gd` already exists and is already bound to generator seed/configuration.

Today the Moon sampler receives the feature catalog but does not yet use it to significantly shape `signed_distance_m`.

That makes the catalog an especially clean place to introduce deterministic bounded features such as:

```text
CRATER
RIDGE
HILL
BASIN
CANYON
FAULT
CAVE_NETWORK
LAVA_TUBE
ARCH
CLIFF_ZONE
SINKHOLE
```

without inventing a second world-geometry owner.

### 2.4 Runtime digging already uses useful volumetric primitives

MW4 excavation currently operates on a swept capsule.

That primitive is useful for gameplay, but the same mathematical family can be reused by generation code for:

- cave tunnels;
- lava tubes;
- elongated erosion cuts;
- canyon centerline cuts;
- fracture corridors.

Important boundary:

```text
GENERATION MUST NOT REPLAY MILLIONS OF MW4 DIG OPERATIONS.
```

Generation should evaluate equivalent field operators directly into revision-0 Matter samples.

Gameplay mutation remains MW4/MW10 and continues to create real revisions, journals, material outputs and persistence state.

## 3. Core canonical rule

The generated mesh must never become the canonical terrain truth.

Correct ownership:

```text
seed
+ generator version
+ PlanetGenerationProfile
+ FeatureCatalog
        ↓
procedural Matter field
        ↓
Matter bricks
        ↓
RL2/RL3 representation
        ↓
render/collision mesh
```

Runtime:

```text
procedural revision 0
        ↓
MW4 / MW10 mutation
        ↓
changed Matter brick snapshot
        ↓
representation invalidation
        ↓
same meshing path
```

Forbidden architecture:

```text
procedural mesh
→ boolean edit mesh
→ mesh becomes terrain truth
```

The mesh remains disposable and reconstructable.

## 4. Generation versus gameplay mutation

This separation is mandatory.

### Generation

```text
generator seed
+ generator version
+ profiles
+ feature catalog
→ deterministic Matter revision 0
```

Generation:

- has no gameplay actor;
- consumes no mining energy;
- emits no MatterMaterialBatch;
- creates no Item Graph resource;
- creates no MW4 mutation journal;
- is deterministic for the same generator identity.

### Gameplay mutation

```text
revision 0
→ player/tool action
→ MW4 or MW10
→ revision 1+
→ material yield
→ Item Graph
→ persistence/replication
```

This preserves mass/economy semantics and prevents initial world generation from appearing as historical mining.

## 5. Proposed procedural field composition

WORLDGEN1 should build terrain as a layered deterministic field rather than one monolithic noise function.

```text
Planet Base
    ↓
Macro Planet Shape
    ↓
Tectonic / Large Relief
    ↓
Erosion-scale Relief
    ↓
Deterministic Feature Catalog
    ↓
Underground Volumes
    ↓
Geological / Material Stratification
    ↓
Matter sample
```

### 5.1 Planet base

Initial forms:

- sphere;
- oblate/ellipsoidal body where physically appropriate;
- bounded radial variation.

The base defines global body identity and coordinate frame. It is not expected to carry detailed terrain.

### 5.2 Macro relief

Scale: tens to thousands of kilometres depending on body size.

Possible outputs:

- continental/highland provinces;
- oceanic or low basins;
- giant impact basins;
- volcanic provinces;
- broad plateaus.

The purpose is silhouette and planetary-scale diversity.

### 5.3 Mountain / ridge systems

Scale: hundreds of metres to hundreds of kilometres.

Use structured ridge fields rather than only isotropic noise.

Desired properties:

- coherent chains;
- varying ridge width;
- asymmetric slopes;
- branching;
- highland clusters;
- erosion-sensitive saddles.

A good world should read as geology, not as uniformly perturbed noise.

### 5.4 Hills and local relief

Scale: metres to kilometres.

Used for:

- rolling terrain;
- hummocks;
- dunes where appropriate;
- talus-like local variation;
- low relief between larger structures.

### 5.5 Ravines and canyons

A canyon should be representable as a path/spline plus a cross-section profile.

Conceptually:

```text
path(s)
+ width(s)
+ depth(s)
+ wall profile(s)
+ local warp
→ subtractive field
```

This permits:

- winding ravines;
- branching gullies;
- very wide canyon systems;
- steep slot canyons;
- gradually widening valleys.

Because the terrain is volumetric, a canyon can intersect caves or create arches/overhangs without switching representation models.

### 5.6 Craters

Feature definition may include:

- center;
- radius;
- depth;
- rim height;
- rim width;
- central peak;
- ejecta roughness;
- erosion age;
- seed.

A crater is therefore more than a simple spherical subtraction.

### 5.7 Cliffs, overhangs and arches

These are important because they distinguish volumetric terrain from a heightmap.

The field must allow multiple solid/empty transitions along a radial or vertical line.

Examples:

- undercut cliff;
- rock arch;
- natural bridge;
- overhang;
- suspended ledge.

They must not require a separate mesh-only object type.

### 5.8 Caves and lava tubes

Caves are a first-class WORLDGEN1 target.

A cave system can be generated from a deterministic graph:

```text
entrance
  ↓
tunnel
  ├── chamber
  │     └── tunnel
  └── deep branch
        └── chamber
```

Each edge can be expanded into a swept volume with variable radius, direction noise and vertical bias.

Useful operators:

- sphere/ellipsoid chamber;
- capsule segment;
- spline tube;
- locally warped tube;
- union of chambers;
- subtractive cave volume.

This supports:

- natural caves;
- lava tubes;
- mine-like fracture systems;
- sinkholes;
- crater-connected tunnels.

## 6. Scale hierarchy

One generator frequency is not enough.

A desirable hierarchy is:

```text
planet scale
  continents / basins / giant impacts

100–1000 km
  mountain provinces / volcanic provinces

1–100 km
  ridges / valleys / large craters

10 m–10 km
  hills / gullies / local crater fields

0.1–100 m
  rocks / erosion detail / cave entrance detail
```

Every layer must have an explicit scale domain and bounded contribution so that tuning one layer does not unpredictably destroy all others.

## 7. Feature catalog model

Feature catalogs should contain deterministic semantic features, not baked meshes.

Possible conceptual entries:

```text
feature/crater/000142
  type = CRATER
  center
  radius
  depth
  rim_height
  erosion
  seed
```

```text
feature/canyon/000551
  type = CANYON
  path
  width_profile
  depth_profile
  wall_profile
  seed
```

```text
feature/cave-system/0032
  type = CAVE_NETWORK
  bounds
  graph_seed
  chamber_density
  tunnel_radius_range
  vertical_bias
```

The exact DTOs are intentionally deferred until WG1.0.

Hard requirements:

- canonical IDs;
- deterministic ordering;
- generator-version binding;
- checksum/hash binding;
- bounded spatial extent for local features;
- no server-process identity in feature identity.

## 8. Sparse persistence advantage

The existing lazy materialization model enables a strong storage strategy.

A mostly untouched planet may be represented by:

```text
PlanetGenerationProfile
generator seed/version
FeatureCatalog
MaterialCatalog
+
only mutated Matter brick snapshots
```

Unmodified bricks reconstruct from the same deterministic revision-0 generator.

Modified bricks are loaded from canonical persistence.

Conceptually:

```text
store has brick?
    ├─ yes → canonical mutated snapshot
    └─ no  → regenerate deterministic revision 0
```

This is one of the most valuable properties of the current architecture for large worlds.

WORLDGEN1 must preserve it.

## 9. Generator identity and compatibility

A procedural planet is only reconstructable if generator identity is durable.

At minimum the world must bind:

- generator ID;
- generator semantic version;
- generator seed;
- planet/body profile checksum;
- feature catalog hash;
- material catalog hash.

A later generator upgrade must not silently reinterpret old persistent worlds.

Possible future compatibility strategies:

- retain historical generator implementation versions;
- explicit world migration;
- materialize affected old regions before migration;
- versioned feature/profile adapters.

Silent generator drift is forbidden.

## 10. Multi-region and distributed-world correctness

Generation must be independent of the server process that happens to own a region.

Required invariant:

```text
sample(body, position, generator identity)
```

returns the same revision-0 result on every authority.

A feature crossing region A/B must not be split into two independently invented features.

The feature identity and field evaluation are global/body-fixed; region ownership only determines which authority evaluates/materializes a brick.

MW10 remains a runtime mutation transaction owner.

```text
cross-region generated canyon ≠ MW10 operation
cross-region player excavation = MW10 when one canonical mutation spans regions
```

## 11. Multi-LOD strategy

A planet cannot keep excavation-grade Matter resolution everywhere.

WORLDGEN1 must support the same underlying world function at different representation scales.

Conceptually:

```text
far planet
  macro representation

regional distance
  low/medium sampled terrain

near player
  high-resolution Matter bricks

active digging volume
  highest required local detail
```

The canonical generator remains deterministic; representations may differ in sampling density.

Acceptance must include:

- no visible cracks at representation/LOD seams;
- stable feature positions across LOD;
- no cave entrance appearing/disappearing incorrectly due only to LOD transition;
- bounded memory and materialization cost;
- no full-planet high-resolution voxel allocation.

The exact meshing transition algorithm is a later implementation decision and must remain under representation ownership rather than becoming WORLDGEN1 canonical state.

## 12. Geological/material generation

Geometry and material composition should be generated together but remain separable concerns.

Possible fields:

- surface soil/regolith;
- compacted layer;
- sediment;
- fractured rock;
- competent bedrock;
- ore bodies;
- ice;
- volcanic material;
- temperature;
- porosity;
- integrity.

Example:

```text
surface
  loose soil
  compacted soil
  weathered rock
  fractured basalt
  competent basalt
  ore vein / inclusion
```

A canyon or cave therefore exposes the actual generated stratigraphy rather than applying a cosmetic wall texture.

## 13. Planet archetypes

WORLDGEN1 should make body variety a profile problem, not a new code path per planet.

### Moon-like

- low erosion;
- high crater density;
- regolith shell;
- basalt;
- giant impact basins;
- lava tubes.

### Earth-like

- strong large-scale relief;
- mountain chains;
- erosion valleys;
- deeper soils;
- sedimentary/igneous variation;
- extensive cave systems.

### Mars-like

- giant shield volcanoes;
- very large canyon systems;
- cratered terrain;
- dunes/local aeolian relief;
- lava tubes;
- low recent erosion.

### Volcanic alien world

- calderas;
- sharp basaltic ridges;
- fractured plains;
- lava channels/tubes;
- high cave connectivity.

The architecture should allow new archetypes mostly by composing profiles/operators/catalogs.

## 14. ECO bridge

WORLDGEN1 should expose derived environmental terrain fields to ECO without making ECO the terrain owner.

Useful derived signals:

- altitude;
- slope;
- aspect;
- curvature;
- soil/regolith depth;
- local material/geology;
- moisture proxy when a hydrology system exists;
- distance to water;
- solar exposure;
- cave/open-air classification;
- roughness;
- drainage/valley class.

Conceptual flow:

```text
Matter/world geometry
        ↓
derived environment fields
        ↓
ECO opportunity/environment sampling
        ↓
biomes / vegetation / ecosystem
```

This allows terrain and ecology to correlate naturally:

- wet valleys → dense vegetation;
- exposed ridges → sparse vegetation;
- cliffs → limited soil;
- cave entrances → specialized ecological zones;
- geology → different soil/mineral conditions.

WG1.7 owns only the derived bridge contract. ECO remains the ecology owner.

## 15. Construction and settlements

Natural terrain and built structures must remain separate canonical systems.

### Matter owns natural/ground geometry

- mountains;
- caves;
- cliffs;
- ravines;
- crater terrain;
- natural rock formations.

### Construction owns built structure identity

- houses;
- bases;
- factories;
- bridges;
- ships;
- stations;
- ruins when represented as actual constructed assemblies.

A procedural settlement generator should therefore produce Construction plans/instances, not bake buildings into terrain density.

```text
World seed
   ├─ terrain generator → Matter
   └─ settlement generator → Construction blueprints/instances
```

Terrain preparation for a building may use bounded cut/fill semantics, but the structure itself remains Construction.

## 16. WORLDGEN1 staged roadmap

### WG1.0 — Matter Feature Operator Contract

Define a deterministic composable feature/operator boundary.

Exit:

- signed-distance/density semantics frozen;
- additive/subtractive operator ownership clear;
- feature identity/hash/version rules;
- no mesh ownership;
- no MW4 journal use during generation;
- exact deterministic tests.

### WG1.1 — Macro Planet Relief

Implement bounded large-scale shape variation.

Target features:

- highland/lowland provinces;
- broad mountain regions;
- basins;
- large smooth relief.

Exit:

- deterministic same-seed reproduction;
- bounded radial displacement;
- no seams across Matter brick/region boundaries.

### WG1.2 — Crater / Ridge / Canyon Generator

Implement structured surface features.

Exit lab contains at least:

- two materially different craters;
- one ridge chain;
- one deep winding canyon;
- one branching ravine;
- deterministic feature catalog reproduction.

### WG1.3 — 3D Cave / Lava Tube Generator

Implement true volumetric underground geometry.

Exit lab contains at least:

- cave entrance;
- multiple chambers;
- branching tunnel;
- lava-tube-like long tunnel;
- one overhang/arch;
- player can subsequently dig into and modify the generated geometry through ordinary Matter mutation.

### WG1.4 — Geological Material Stratification

Generate material composition coherently with geometry.

Exit:

- surface/regolith/rock layers;
- at least one bounded ore/material body;
- excavation returns materials implied by generated geology;
- mass/accounting remains canonical.

### WG1.5 — Multi-LOD Matter Representation

Prove near/high-resolution and far/low-resolution representation of one generated world.

Exit:

- stable feature location across LOD;
- bounded memory;
- no visible/severe collision seam in acceptance topology;
- high-resolution materialization limited to active regions.

### WG1.6 — Planet Archetype Profiles

Create multiple visibly and structurally different worlds from profiles.

Minimum acceptance set:

- Moon-like;
- Earth-like;
- Mars-like or volcanic alien.

The same WORLDGEN1 contracts must serve all profiles.

### WG1.7 — ECO Surface Field Bridge

Expose derived terrain/environment fields to ECO.

Exit:

- deterministic field sampling;
- no ECO ownership of geometry;
- ecological placement responds to slope/altitude/material/topology differences.

### WG1.8 — Procedural Construction Placement

Add bounded settlement/ruin/site generation through canonical Construction.

Exit:

- terrain and Construction remain separate truths;
- placement stable across regeneration/reconnect;
- structures can interact with terrain without being terrain meshes.

### WG1.9 — Full Procedural Planet Lab

Full demonstration:

```text
one generated planetary region/world
+ hills
+ ridge
+ canyon/ravine
+ craters
+ cave network
+ arch/overhang
+ stratified materials
+ multiple LOD
+ ordinary player digging
+ persistence/restart
+ two-client convergence
+ seam crossing
+ optional ECO/Construction composition
```

## 17. Activation gates

WORLDGEN1 has three distinct gates.

### Gate A — DESIGN_NOW

Status: OPEN NOW.

Allowed before P7 finishes:

- architecture;
- documentation;
- operator math prototypes that do not alter production runtime;
- fixture-only visual experiments;
- deterministic research benchmarks.

Not allowed:

- changing P7 canonical owner semantics;
- replacing the active Moon production generator;
- introducing a second terrain truth.

### Gate B — EXECUTABLE_WORLDGEN1

Earliest correct activation point:

```text
P7.7 COMPLETE_MERGED
+
V0_P7_BOUNDED_TERRAIN_MUTATION formally ACCEPTED
+
exact Matter generation/materialization/mutation/representation boundaries frozen
+
available runtime mutation/research slot under current scheduler policy
```

Reason:

By this point the project has proven the entire production chain:

```text
procedural Matter
→ graphical digging
→ runtime mutation
→ material yield
→ persistence
→ two-client convergence
→ seam/multi-region behavior
```

WORLDGEN1 can then expand revision-0 geometry without simultaneously redefining unfinished P7 semantics.

### Gate C — PRODUCT_PROMOTION

WORLDGEN1 may replace/expand default product terrain only after:

```text
V0 PLAYABLE SEAMLESS PLANET ACCEPTED
+
WG1 required stages independently verified
+
performance/LOD/persistence compatibility proven
```

This prevents a promising research generator from becoming an implicit blocker for first V0 composition acceptance.

## 18. First recommended lab

The first executable WORLDGEN1 lab should be intentionally small.

One bounded Matter region must contain:

- one large hill;
- one ridge;
- one deep ravine/canyon;
- two distinct craters;
- one cave system with at least two chambers;
- one through tunnel;
- one overhang or arch;
- at least two geological materials.

Then run:

```text
generate
→ materialize
→ mesh/collision
→ player enters
→ player digs generated hill/canyon/cave
→ ordinary MW4 result
→ representation rebuild
→ restart
→ same generated + mutated world
```

Key acceptance rule:

```text
GENERATED TERRAIN
→ ORDINARY MATTER MUTATION
→ NO SPECIAL-CASE TERRAIN PATH
```

## 19. Stop conditions

Stop and return to architecture if an implementation proposes:

- mesh as canonical terrain state;
- a WORLDGEN1-private persistence store;
- a WORLDGEN1-private replication protocol;
- replaying generated features through MW4 gameplay journals;
- generation-created Item Graph resources;
- storing every unmodified planet brick eagerly;
- server-dependent generator output;
- feature identity derived from authority/server IDs;
- buildings encoded as anonymous terrain density where Construction identity is required;
- whole-planet excavation-grade resolution;
- silent generator-version reinterpretation of persisted worlds.

## 20. Architectural target

The intended long-term composition is:

```text
                         WORLD SEED
                             │
                 ┌───────────┼───────────┐
                 ▼           ▼           ▼
              PLANET      GEOLOGY     CLIMATE
              PROFILE      PROFILE     PROFILE
                 │           │           │
                 └─────┬─────┘           │
                       ▼                 │
               PROCEDURAL MATTER        │
                       │                 │
          ┌────────────┼────────────┐    │
          ▼            ▼            ▼    ▼
       mountains     caves       valleys ECO derived fields
          │            │            │    │
          └────────────┼────────────┘    ▼
                       ▼              ecology
                  Matter bricks
                       │
                       ▼
                  RL2/RL3 mesh
                       │
                       ▼
                  playable world
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
      MW4/MW10                 Construction
   runtime digging        settlements/buildings
```

The central design principle is deliberately simple:

> **WORLDGEN1 creates deterministic revision-0 Matter. Gameplay mutates the same Matter. Meshes, ecology fields and visuals are derived consumers. Construction remains the canonical owner of built structures.**

If preserved, this gives DWS a path to many visually and structurally different planets without multiplying incompatible terrain systems.
