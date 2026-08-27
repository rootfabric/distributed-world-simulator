# ECO.EVO7 LS3.2 — Spatial Cohort Lattice R1 — HARDENED CANDIDATE

**Base:** accepted LS3.0/LS3.1 research substrate `930d975e85601bf41e6b5ce8595c99dafdc361a1`.

## Scope

LS3.2 materializes one bounded spatial metapopulation over the accepted `32 x 32` physical patch. It intentionally does **not** implement reproduction, dispersal, recruitment, competition, persistence, networking, production writes, or a second mutation authority.

R1 freezes:

- 1024 ecological cells;
- exactly 4 slot addresses per cell;
- maximum 4096 materialized ecological records;
- default founder initialization: 256 records;
- one exact canonical ancestor bundle source;
- deterministic placement from a dedicated placement seed;
- environment field accepted only as validated read-only context;
- environment/recipe/cell identity never edits the hereditary bundle and never participates in a mutation seed;
- renderer receives a read-only bounded projection and is not ecological source of truth.

## State identity

Three identities are deliberately separated:

1. `hereditary_pool_hash` — exact bundle identities only;
2. `occupied_slot_addresses_hash` — spatial placement only;
3. `initial_population_hash` — canonical cell/slot ecological state.

Changing the environment recipe with the same founder + placement seeds must preserve all three population identities. Changing only the placement seed may change spatial addresses/population hash but must preserve the hereditary pool. Changing only the founder seed may change heredity but must preserve spatial addresses.

## Evolution boundary

LS3.2 has no reproduction call site. `Evolution ON` fails closed. `Evolution OFF` may advance observation generation while exact hereditary and spatial population identities remain unchanged. Canonical reproduction enters only in LS3.3 before dispersal/recruitment.

## Acceptance

Focused acceptance must prove:

- initial population hash identical across the three LS3.1 counterfactual physical recipes;
- exact same founder bundle copied into all founder records;
- deterministic same-seed replay;
- placement changes only with placement seed;
- Evolution OFF preserves exact bundle identities;
- every cell has exactly four bounded slots and no cell exceeds four occupied records;
- 4096 records succeeds, 4097 fails closed;
- empty and occupied cell hashes are deterministic and distinct;
- renderer projection count/state cannot alter ecological state;
- stale environment and hereditary tamper are rejected;
- nested genome/traits/lineage identities are revalidated, not trusted through an outer bundle checksum;
- founder seed is bound to the one canonical ancestor bundle;
- placement seed + record index are bound to the exact cell/slot address;
- foreign valid founder injection, whole foreign-population substitution, record relocation, revision drift, authority escalation, premature evolution state, and unexpected hidden fields fail closed even after ecological hashes are recomputed;
- no biome-label, mutation, reproduction, persistence, network or production-authority shortcut.

## Authority boundary

```text
world_write                    = false
ecology_production_write       = false
persistence_write              = false
network_replication_write      = false
xfer_authority                 = false
alternate_mutation_authority   = false
biome_classifier_ecology_input = false
```

## Exact focused evidence

Engine: `4.7.1.stable.double.custom_build.a13da4feb`.

Before publication, the exact four candidate files were materialized locally over the accepted LS3.0/LS3.1 source and the focused LS3.2 acceptance passed:

- `ECO.EVO7 LS3.2 Spatial Cohort Lattice: PASS (2382 assertions)`;
- focused runner rc = 0;
- tested lattice blob: `378bbd3e1919d0edcd0cc1b1001e7c9a3697768e`;
- tested acceptance blob: `3023a9d698bc8ae94cebd822251440e87add8f81`.

The hardened validator now uses exact snapshot/cell/slot/record/bundle schemas, deep hereditary contract validation, canonical founder reconstruction from `founder_seed`, and canonical slot reconstruction from `placement_seed + record_index`. The published file blobs must match these locally tested bytes exactly before candidate freeze.

## Next boundary

LS3.3 Dispersal / Recruitment remains forbidden until this LS3.2 candidate passes exact-double full-chain machine closure and fresh semantic review.
