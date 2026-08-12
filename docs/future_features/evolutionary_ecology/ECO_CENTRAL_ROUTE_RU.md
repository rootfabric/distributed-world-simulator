# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.1 SEED DISPERSAL KERNEL`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Accepted foundation

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A                ACCEPTED
ECO.CAL1-B                ACCEPTED
ECO.CAL1-C                ACCEPTED
ECO.CAL1-D                ACCEPTED
ECO.CAL1-E                ACCEPTED
ECO.CAL1-F                ACCEPTED / ROBUST_UNITY_CALIBRATION
```

Canonical hashes:

- CAL1-A `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- CAL1-C `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`;
- CAL1-D `c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`;
- CAL1-E `6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814`;
- CAL1-F `f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed`.

CAL1-F canonical classification: `ROBUST_UNITY_CALIBRATION`.

CAL1-F evidence: five distinct deterministic seed signatures; 100% multi-member Pareto retention in seed contexts; two environment Pareto signatures; zero density/disturbance monotonicity violations; ±15% mechanism envelope with min/mean Pareto Jaccard `1.0`; three resource signatures; twenty pool contexts; zero pairwise/full-pool resource contradictions; exact fresh-process replay.

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
EVO1 / P2.1 ← CURRENT
Seed Dispersal Kernel
   ↓
P2.2 Establishment / Recruitment / Seed Bank
   ↓
P2.3 Local Population Turnover + Succession
   ↓
P2.4 Patch Colonization / Isolation / Migration
   ↓
P2.5 Disturbance + Recovery
   ↓
P2.6 Long-Horizon Biogeography
   ↓
P2.7 Lineage Divergence / Speciation Candidate Diagnostics
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

EVO1 final acceptance remains:

`NO_BIOME_SPECIES_TABLES_AND_MULTIPLE_CAUSALLY_EXPLAINABLE_PERSISTENT_COMMUNITIES`.

## P2.1 boundary

P2.1 is the first step that creates autonomous spatial ecology transport. It does **not** establish or kill plants; recruitment belongs to P2.2.

Required semantics:

```text
source reproductive output
+ inherited/effective dispersal distance
+ deterministic transport context
        ↓
portable seed packets / spatial destination distribution
```

P2.1 must preserve:

- emitted seed-count conservation within explicit boundary-loss accounting;
- lineage/genome identity on every packet;
- deterministic replay from the same source/event/seed;
- different transport under different inherited dispersal distance;
- release-height effect from accepted CAL1-D semantics;
- anisotropic transport via explicit environmental vector/context, not biome lookup;
- local and long-tail transport bins;
- no species placement table;
- no establishment probability, carrying capacity or seed-bank survival logic yet.

The existing P1C dynamic-abundance experiment is not a dispersal implementation: it advances independent patch biomass and does not move lineage propagules between patches. P2.1 therefore adds the missing spatial transport kernel rather than extending that old abundance fixture.

## Calibration inheritance

The accepted CAL1-F UNITY profile remains the EVO0 causal baseline. P2.1 must not reopen CAL1 coefficient tuning. Any new dispersal-kernel shape parameters must be explicit transport semantics and tested for conservation/determinism rather than tuned to create desired species geography.

## Global boundary

EVO1 remains standalone/research-only. It may own ecology semantics and portable ecology state meaning, but it must not create private replacements for canonical spatial/time/environment/runtime foundations. `XFER1/LIVE` remain deferred until their global contracts exist.

Current resolver: `IMPLEMENT AND VALIDATE ECO.EVO1/P2.1 SEED DISPERSAL KERNEL`.
