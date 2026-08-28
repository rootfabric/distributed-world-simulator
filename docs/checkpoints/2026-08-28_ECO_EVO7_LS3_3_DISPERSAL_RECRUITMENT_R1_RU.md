# ECO.EVO7 LS3.3 — Dispersal / Recruitment R1 — CANDIDATE

**Base:** accepted LS3.2 `c0cf7a8d37f73e5ffeabd856e70d7ee05e8d5541`.

## Scope

LS3.3 вводит первую настоящую spatial ecology динамику и строго сохраняет causal order:

`parent bundle -> canonical reproduce_bundle() -> immutable child identity -> deterministic dispersal -> destination physical environment -> establishment/recruitment`.

R1 использует generational replacement: родители порождают deterministic offspring candidates, но сами автоматически не копируются в следующее поколение. Успешные recruits формируют новое поколение. Это позволяет локальные extinction/colonization уже в LS3.3 без premature competition.

## Frozen rules

- ровно 2 offspring candidates на parent record;
- единственный offspring authority — `LineageExtension.reproduce_bundle()`;
- mutation seed выводится только из pre-environment `reproductive_identity` + hereditary bundle identity + evolution seed + generation + offspring ordinal; spatial `record_id/cell/slot` исключены;
- founder `reproductive_identity` выводится из founder seed + stable LS3.2 `record_index` + bundle checksum и не зависит от placement cell/slot; для recruited child он равен pre-environment mutation candidate hash;
- dispersal seed выводится только из immutable child/lineage identity + evolution seed + generation + offspring ordinal;
- distance использует наследуемый `seed_dispersal_distance_m`;
- direction/distance/destination фиксируются до чтения destination environment;
- out-of-patch rule: `REJECT`, без clip/wrap;
- local establishment использует accepted FFF6 shadow fitness evaluation, собранную из LS3.1 physical cell fields;
- environment влияет на establishment success, но не на child or route identity;
- максимум 4 recruits на destination cell;
- при overflow выбор bounded slots идёт по environment-neutral `candidate_hash`, поэтому LS3.4 competition не реализуется преждевременно.

## Acceptance

1. Same parents => same generation-one mutation candidate pool across all three counterfactual recipes.
2. Same children => same candidate-to-destination mapping across recipes.
3. Recruitment evidence and establishment successes may differ across recipes.
4. By generation 3 occupied/population maps diverge for strong physical recipes.
5. Exact replay reproduces candidate, route and final population/spatial hashes.
6. Evolution OFF blocks reproduction/dispersal/recruitment and preserves population/heredity.
7. Route evidence proves parent + delta = destination and binds recruitment events to exact route hashes.
8. Source guard proves exactly one canonical `reproduce_bundle()` call and no alternate RNG/persistence/network/biome/competition authority.

## Authority boundary

```text
world_write                    = false
ecological_production_write    = false
persistence_write              = false
network_replication_write      = false
xfer_authority                 = false
alternate_mutation_authority   = false
competition_authority          = false
biome_classifier_ecology_input = false
```

## Next boundary

LS3.4 owns local competition (light/water/space). LS3.3 capacity conflict handling is deliberately identity-only and must not be treated as competition fitness.

## Pre-publication exact-double evidence

Engine: `4.7.1.stable.double.custom_build.a13da4feb`.

- focused LS3.3 R3: `PASS (44 assertions)`;
- inherited full chain: `45 / 19 / 48 / 51 / LS2 smoke / 89 / 11369 / 24 / spatial 1024 / LS3.2 2382 / LS3.3 44`;
- runner rc: `0`;
- runtime: `82s`;
- acceptance uses a deterministic real-Earth land center `Vector3(-0.5, -0.86602540378444, 0).normalized()` whose 32x32 patch is 1024/1024 land cells; the engine itself remains fail-closed on non-land recruitment.

Full exact-Git artifact closure and fresh semantic review are still required before LS3.4.

## Causal identity hardening R2

Fresh semantic inspection rejected the first published candidate because its mutation seed used spatial `parent_record_id`, whose recruited form includes destination/slot. R2 introduces a separate pre-environment `reproductive_identity`:

- founder reproductive identity comes from LS3.2 deterministic placement identity, which is environment-neutral;
- recruited child reproductive identity is its mutation candidate hash, fixed before destination environment is read;
- mutation seed uses reproductive identity + hereditary bundle + evolution seed + generation + offspring ordinal;
- mutation seed explicitly excludes spatial record id, cell and slot;
- mutation candidate hash excludes parent record/cell address;
- acceptance proves relocating a parent record while preserving reproductive identity cannot change the mutation seed.

This prevents previous recruitment geography from feeding back into future mutation randomness except through the biologically intended selection of which reproductive identities survive.

## Causal identity hardening R3

Fresh R2 semantic review found one remaining geography coupling limited to founder generation: founder `reproductive_identity` copied the LS3.2 spatial `record_id`, which encodes cell/slot. R3 replaces it with a stable founder ordinal identity derived from `founder_seed + record_index + bundle_checksum`. Acceptance adds a placement counterfactual proving that changing only `placement_seed` cannot change the generation-one mutation candidate pool.
