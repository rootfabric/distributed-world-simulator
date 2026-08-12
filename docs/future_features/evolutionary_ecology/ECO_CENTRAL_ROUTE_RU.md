# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.3 EXECUTE_NOW`.

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
```

Canonical hashes:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
P2.2    633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86
```

P2.2 exact Windows findings: favourable/dry/flooded recruits `46/21/26`; low/high dormancy bank `8/66`; short/long half-life bank `4/61`; reactivation `33`; boundary export `80`.

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
P2.1 Seed Dispersal Kernel ACCEPTED
   ↓
P2.2 Establishment / Recruitment / Seed Bank ACCEPTED
   ↓
P2.3 Local Population Turnover + Succession ← CURRENT
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

## P2.2 accepted meaning

P2.2 established persistent local propagule memory while preserving exact integer conservation. Germination, establishment and seed-bank survival are separate causal stages. High dormancy trades immediate recruitment for persistent bank; long half-life preserves historical opportunity; improved conditions can reactivate dormant propagules. Outside-domain propagules remain export.

## P2.3 authorization

P2.3 may now connect recruited cohorts and seed-bank memory into repeated local time steps.

Required scope:

- cohort/population truth rather than one entity per plant;
- explicit adult cohort age, abundance/biomass and lineage identity;
- resource-causal growth and stress mortality;
- lifespan/age turnover;
- local density/capacity competition without a species lookup table;
- repeated recruitment from current reproduction and existing seed bank;
- succession measured as changing lineage abundance through time;
- deterministic history/hash replay.

Strict boundary:

- no inter-patch propagule transfer or migration graph in P2.3;
- no explicit disturbance-event scheduler (P2.5);
- no long-horizon regional biogeography (P2.6);
- no speciation decision (P2.7).

Current resolver: `IMPLEMENT EVO1/P2.3 LOCAL POPULATION TURNOVER + SUCCESSION`.
