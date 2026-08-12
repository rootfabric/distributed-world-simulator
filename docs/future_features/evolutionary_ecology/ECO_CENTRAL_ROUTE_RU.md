# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.4 EXECUTE_NOW`.

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
```

Canonical hashes:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
P2.2    633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86
P2.3    15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e
```

## P2.3 accepted evidence

Exact Windows Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

```text
EARLY initial share       0.875000000000
BANKED initial share      0.125000000000
BANKED pre-change         0.199612211554
BANKED shade final        0.964707699557
BANKED open final         0.369379521845
shade delta               0.595328177712
banked gain               0.765095488003
reactivated               48
reproduction events       15
emitted                   325
short mortality           0.050232535701
long mortality            0.028476366298
max biomass               0.101663621317
```

Acceptance: 168 assertions PASS; fresh-process A/B exact hash match.

Historical parser finding `Engine shadows a native class` was repaired only by alias rename `Engine -> PopulationEngine`; model semantics did not change.

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
P2.4 Patch Colonization / Isolation / Migration ← CURRENT
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

## P2.4 boundary

P2.4 may now turn P2.3 export accounting into explicit research-scale inter-patch movement. It must preserve:

- P2.1 propagule spatial semantics;
- P2.2 establishment/seed-bank semantics;
- P2.3 local turnover/succession semantics;
- lineage/genome/reproduction-event identity;
- cohort-bounded truth.

It must demonstrate causally that nearby connected patches colonize more readily than isolated patches, and that changed connectivity/history changes persistent community state without a biome/species placement table.

P2.4 remains research-only and must not claim canonical simulator Spatial Domain Fabric ownership. Patch graph/geometry here is a local experiment input. `XFER1/LIVE` remain deferred to global foundations.

P2.4 must not introduce explicit disturbance-event scheduling; that begins at P2.5.

Current resolver: `IMPLEMENT EVO1/P2.4 PATCH COLONIZATION / ISOLATION / MIGRATION`.
