# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.4 ACCEPTED / P2.5 EXECUTE_NOW`.

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
ECO.EVO1 / P2.2           ACCEPTED
ECO.EVO1 / P2.3           ACCEPTED
ECO.EVO1 / P2.4           ACCEPTED
```

Canonical hashes:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
P2.2    633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86
P2.3    15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e
P2.4    78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97
```

P2.4 exact Windows evidence:

```text
near_arrived=800
far_arrived=160
near_recruited=430
far_recruited=87
near_short=84
near_long=346
far_short=0
far_long=87
near_long_share=0.804651162791
far_long_share=1.000000000000
west_routed=0
```

This proves causal distance isolation and transport-direction filtering through actual P2.1 packet coordinates.

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
P2.1 Seed Dispersal Kernel ACCEPTED
   ↓
P2.2 Establishment / Recruitment / Seed Bank ACCEPTED
   ↓
P2.3 Local Population Turnover + Succession ACCEPTED
   ↓
P2.4 Patch Colonization / Isolation / Migration ACCEPTED
   ↓
P2.5 Disturbance + Recovery ← EXECUTE NOW
   ↓
P2.6 Long-Horizon Biogeography
   ↓
P2.7 Lineage Divergence / Speciation Candidate Diagnostics
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

EVO1 final acceptance remains:

`NO_BIOME_SPECIES_TABLES_AND_MULTIPLE_CAUSALLY_EXPLAINABLE_PERSISTENT_COMMUNITIES`.

## P2.5 boundary

P2.5 introduces explicit disturbance events and recovery chronology. It must not reinterpret a disturbance as a species-specific modifier or biome table.

The event contract is decomposed into causal channels:

```text
mechanical_severity          -> CAL1-D adult exposure/anchoring survival
seed_bank_mortality_fraction -> direct event pressure on dormant propagules
```

Recovery must preserve accepted ecology semantics:

- adult turnover/growth remains compatible with P2.3 coefficients;
- surviving seed-bank cohorts reactivate through P2.2;
- disturbance history can alter later lineage abundance without placing species;
- state and damage/recovery ledgers remain deterministic and conservative.

P2.5 remains research-only. It does not claim canonical environment-event, time-fabric, persistence, world lifecycle, or work-budget ownership. Those production bridges remain XFER/LIVE concerns.

P2.6 stays blocked until exact Windows P2.5 acceptance.

Current resolver: `IMPLEMENT EVO1/P2.5 DISTURBANCE + RECOVERY`.
