# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.2 ESTABLISHMENT + RECRUITMENT + SEED BANK`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Accepted foundation

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1           ACCEPTED
```

Canonical hashes:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
```

P2.1 exact evidence includes 811 assertions PASS, exact fresh-process replay, inherited-distance ratio `6.0`, release-height ratio `2.0`, explicit boundary export `80`, local seeds `70` and long-tail seeds `10`.

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
P2.1 Seed Dispersal Kernel ACCEPTED
   ↓
P2.2 Establishment / Recruitment / Seed Bank ← CURRENT
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

## Accepted P2.1 truth

P2.1 owns transport of propagule cohorts only. It uses bounded lineage-preserving seed packets, exact count conservation, explicit domain export, inherited dispersal distance, release-height scaling and deterministic anisotropic transport context.

It does **not** decide establishment.

## P2.2 purpose

P2.2 consumes P2.1 inside-domain seed packets and introduces the first persistent local propagule state:

- environment-dependent germination opportunity;
- deterministic recruitment cohort counts;
- non-germinated viable seed-bank cohorts;
- seed-bank aging and viability loss;
- explicit failure/death accounting;
- lineage/genome/event identity preservation.

P2.2 must stay cohort-based. It must not create one entity per seed.

P2.2 must not introduce biome/species placement tables. Environment suitability must emerge from genome/environment relations already present in the ECO model.

P2.2 also does not yet own multi-cycle local population turnover, succession, regional migration or disturbance recovery. Those remain P2.3+.

## Global boundary

Standalone EVO remains research-only. ECO owns ecology semantics, not canonical spatial/weather/runtime foundations. `XFER1/LIVE` remain deferred until global contracts exist.

Current resolver: `IMPLEMENT EVO1/P2.2 ESTABLISHMENT / RECRUITMENT / SEED BANK`.
