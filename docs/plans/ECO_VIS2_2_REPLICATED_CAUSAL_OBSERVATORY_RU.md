# ECO VIS2.2 — Replicated Causal Experiment Observatory

Дата открытия: 2026-08-17

Статус: **OPEN / DESIGN FROZEN FOR FIRST IMPLEMENTATION SLICE**

Exact base:

`feature/eco-vis2-1v-treatment-realtime-lod @ 731f9d892e7747d391a79b88b24bae69769b3340`

VIS2.1-V at that base is independently accepted and formally closed.

## 1. Goal

VIS2.1 proved one deterministic paired CONTROL/TREATMENT experiment using common random numbers and one visible Treatment world.

VIS2.2 answers the next scientific question:

> Is the observed Treatment effect robust across several independent stochastic realizations, or is it specific to one common-random-number root?

The stage runs a bounded set of deterministic paired replicates from the same canonical fork state.

For every replicate `r`:

```text
CONTROL[r]   and   TREATMENT[r]
```

must share exactly the same replicate random root.

Different replicates use different deterministic roots.

The result is an effect distribution rather than one trajectory.

## 2. Critical causality rule

Within each replicate:

```text
control_root[r] == treatment_root[r]
```

The root may depend on:

- a VIS2.2 replicate RNG domain;
- immutable fork identity/hash;
- replicate index.

The root MUST NOT depend on:

- `CONTROL` / `TREATMENT`;
- branch id;
- experiment id;
- treatment profile name;
- treatment intensity.

Treatment may differ from Control only because environment forcing changes fitness and therefore later survival/recruitment/dispersal outcomes.

## 3. Common fork

All replicates begin from one immutable canonical fork state at generation `N`.

Generation `N` itself is identical for every Control and Treatment replicate.

Treatment starts at:

```text
N + 1
```

The fork state is deep-copied into every runner. No replicate may mutate the stored immutable fork.

## 4. Bounded replicate model

Initial contract:

```text
default_replicates = 8
minimum_replicates = 2
maximum_replicates = 16
branch_cache_window = 64 generations
aggregate_series_window = 64 generations
```

The number of replicates is deliberately bounded.

Expected asymptotic work per visible generation:

```text
O(replicates * cache_window)
```

No operation may replay from the original fork merely to rebuild observatory charts after normal rewind/profile switching.

## 5. Rendering rule

VIS2.2 must preserve the VIS2.1/VIS2.1-V rendering boundary:

```text
CONTROL replicates       = data-only
non-selected TREATMENT   = data-only
selected TREATMENT       = exactly one rendered ecology field
```

There must never be 8 or 16 rendered ecology worlds.

The selected Treatment replicate reuses VIS2.1-V realtime NEAR/MID/FAR LOD.

Changing the selected visible replicate is a presentation action only and must not mutate any replicate simulation state.

## 6. Aggregate observatory

For each paired generation, compute deterministic aggregate Treatment-minus-Control effects across replicates.

Minimum fields:

- replicate_count;
- generation;
- mean population delta;
- median population delta;
- min/max population delta;
- mean fitness delta;
- median fitness delta;
- min/max fitness delta;
- mean unique-genome delta;
- mean birth delta;
- mean death delta;
- mean survivor delta;
- mean represented-biomass delta;
- mean alpha-share delta;
- positive/zero/negative effect counts for population and fitness;
- exact per-replicate paired trace identities.

Optional presentation statistics may include deterministic standard deviation and quartiles, but VIS2.2 does not claim formal hypothesis testing or p-values.

## 7. Deterministic aggregate semantics

Aggregation order must be canonical by numeric replicate index.

Floating-point aggregate calculations must use one fixed order and one documented rounding policy where serialized/display hashes require rounding.

Running the same fork/configuration twice must reproduce byte-identical aggregate trace output.

Changing which replicate is visible must not change aggregate output.

## 8. Rewind and rebranch

All replicates share one visible generation cursor.

Left rewind clamps to the common oldest cached generation available across all replicate Control/Treatment runners.

Changing Treatment profile/intensity after rewind:

- preserves history through the current visible generation;
- truncates only future Treatment state in every replicate;
- applies the new Treatment beginning at visible generation + 1;
- does not rewind or alter Control branches unnecessarily;
- preserves every replicate root;
- does not replay from the original fork if the current generation is still cached.

## 9. Root observability

Expose enough state for tests/review to prove:

- one deterministic master/fork identity;
- one root per replicate;
- Control/Treatment root equality inside every replicate;
- root inequality across distinct replicate indexes, except cryptographic collision;
- root stability across rewind/rebranch/restart.

Do not expose random mutable global RNG state.

## 10. UI

VIS2.2 panel should add a compact replicated-effect observatory:

- current replicate count;
- selected visible replicate;
- Treatment profile/intensity;
- mean Control-vs-Treatment effect curves;
- effect range/band across replicates;
- positive/negative replicate counts;
- current selected replicate's individual delta;
- aggregate mean delta.

The existing VIS2.1 comparison remains useful for the selected replicate, but the VIS2.2 aggregate panel is authoritative for replicated-effect interpretation.

## 11. Controls

Provisional controls:

```text
F          create replicated fork
Space      play/pause
Left/Right shared paired generation
R          restart all replicates from immutable fork
[ / ]      previous/next visible Treatment replicate
2          DROUGHT
3          FLOOD
4          NUTRIENT_PULSE
5          SHADE
- / +      treatment intensity
```

Changing visible replicate must never trigger simulation replay.

## 12. Lifecycle

Every data-only runner created by VIS2.2 must have explicit ownership and clean teardown.

The VIS2.1-V derived-scene leak investigation is now a permanent regression lesson:

- do not create intermediate scripted PackedScene states that instantiate owned Node members before the final root script state exists;
- dynamically created Node runners must be attached/freed by one clear owner;
- RefCounted models/resources must not survive scene shutdown;
- final gate must reject ObjectDB, RID, resource/cache and StringName shutdown leaks even with exit code 0.

## 13. Acceptance harness

`RUN_ECO_VIS2_2_TESTS.ps1` must first run the full independently accepted VIS2.1-V gate.

VIS2.2-specific gate must fail closed on:

- exact Godot mismatch;
- parser/runtime errors;
- timeout;
- missing PASS marker;
- ObjectDB leak;
- RID leak;
- resource/cache leak;
- StringName leak.

Use the accepted VIS2.1-V shutdown matcher rather than inventing a weaker parallel implementation.

## 14. First implementation split

### VIS2.2-A — Replicate Root / Runner Set

New data-only orchestration layer:

- deterministic replicate roots;
- identical immutable fork copies;
- paired Control/Treatment runners per replicate;
- bounded cache operations;
- restart/rewind/rebranch semantics;
- no UI and no new renderer.

### VIS2.2-B — Aggregate Model

Pure RefCounted model:

- consumes canonical paired trace points;
- computes deterministic per-generation replicated effects;
- stores <=64 aggregate points;
- no SceneTree and no simulation.

### VIS2.2-C — Observatory Panel

Presentation-only aggregate charts and selected-replicate status.

### VIS2.2-D — Integrated Lab

- exactly one selected Treatment renderer;
- reuse VIS2.1-V LOD;
- all other runners data-only;
- routed spectator input;
- clean lifecycle;
- Windows automated + graphical validation.

## 15. Hard acceptance invariants

VIS2.2 cannot close unless tests prove all of the following:

1. Same immutable fork for every replicate.
2. Control/Treatment root equality inside each replicate.
3. Deterministically distinct roots across replicate indexes.
4. Fork generation structurally identical across every branch.
5. Treatment begins only at fork+1.
6. Camera/visible-replicate selection cannot mutate traces.
7. Exactly one visible ecology field.
8. All Control and unselected Treatment replicates are data-only.
9. Per-runner caches <=64.
10. Aggregate history <=64.
11. Rewind clamps to common cache floor.
12. Rebranch does not replay from fork when cached state is available.
13. Restart after eviction exactly reproduces deterministic results.
14. Aggregate output is deterministic across identical runs.
15. Selected-replicate changes leave aggregate hashes unchanged.
16. Whole-field PH5 rebuild remains zero after fork.
17. No ObjectDB/RID/resource/StringName shutdown leak.
18. Exact Godot 4.7.1 double Windows gate passes.
19. Graphical lab shows one Treatment world plus aggregate replicated-effect observatory.
20. Fresh independent review returns PASS.

## 16. Boundary

VIS2.2 remains a research/observer stage.

It does not authorize:

- production ecology authority;
- gameplay/network ownership;
- production persistence schema;
- distributed region ownership;
- server handoff semantics;
- canonical world mutation by visual observer code.

Permanent boundary:

```text
research ecology state != visual observer state != production/network authority
```
