# ECO.EVO7 LS3.4 — Local Competition R1 — CANDIDATE

**Base:** accepted LS3.3 `a8050ab310257949fd7f1d1862eecd3e72050af9`.

## Scope

LS3.4 adds one deterministic, order-independent local competition pass **after** LS3.3 recruitment. It does not own reproduction, mutation, dispersal, biome classification, rendering, persistence, networking, or production ecology authority.

Frozen causal order:

```text
LS3.3 parent/reproduction/mutation/dispersal/recruitment
  -> pre-competition recruited records
  -> realized functional phenotype in physical cell environment
  -> understory light feedback + bounded soil-water allocation + geometric space overlap
  -> resource balance
  -> deterministic survival
```

Competition cannot rewrite the current generation's `candidate_pool_hash`, `dispersal_pool_hash`, or `recruitment_hash`.

## Neighborhood policy

R1 freezes:

- **water:** same ecological cell, allocated by accepted `SoilWaterField`; total uptake cannot exceed water available after evaporation;
- **light:** accepted `UnderstoryLightField`, physical crown geometry and Beer-Lambert attenuation;
- **space/root geometry:** Moore radius 1 by default;
- interaction radius may expand to at most 2 cells only when realized crown/root-spread phenotype exceeds one 16 m cell.

Policy identity:
`SAME_CELL_WATER+MOORE_GEOMETRY+TRAIT_RADIUS`.

## Accepted trait/resource surfaces

Competition consumes existing EVO7/FFF outputs:

- realized height / crown radius / crown density;
- leaf area index proxy;
- realized root depth / root spread;
- root-shoot ratio;
- transpiration demand / shade output;
- functional phenotype maintenance cost;
- accepted `PlantResourceModel` root construction + structural costs.

Root-heavy investment is therefore not free: realized root maintenance and canonical root construction cost are explicit components of competition evidence. R1 survival floor is frozen at `realized_resource_balance >= -0.35`; it is a research calibration threshold, not a species/biome rule.

## Order independence

All records are canonicalized by `record_id` before phenotype/light/water/geometry evaluation. `UnderstoryLightField` and `SoilWaterField` also canonicalize identities. Pair geometry iterates a canonical pair order. Field and survivor hashes therefore cannot depend on input array permutation.

## Acceptance

R1 must prove:

1. local total water uptake never exceeds available local water;
2. water/resource state never becomes negative;
3. reversing individual evaluation order preserves exact competition field hash and survivors;
4. dense canopy lowers effective light only through the physical understory-light feedback field;
5. root investment has positive measurable construction/maintenance cost;
6. Competition OFF/ON preserves first-generation mutation/dispersal/recruitment identities but changes later community outcome;
7. deterministic replay reproduces exact competition/state hashes;
8. LS3.4 contains no reproduction/mutation/dispersal/biome/renderer/network/persistence shortcut;
9. competition field/snapshot fail closed on negative water and authority escalation even after hash recomputation.

## Authority boundary

```text
world_write                    = false
ecological_production_write    = false
persistence_write              = false
network_replication_write      = false
xfer_authority                 = false
alternate_mutation_authority   = false
competition_authority          = false  # research model has no production authority
biome_classifier_ecology_input = false
```

## Next boundary

LS3.5 Emergent Biomes remains forbidden until exact-double full-chain machine closure and fresh semantic review of the immutable LS3.4 candidate.
