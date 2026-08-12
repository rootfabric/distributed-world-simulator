# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.5 ACCEPTED / P2.6 EXECUTE NOW`.

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
ECO.EVO1 / P2.5           ACCEPTED
```

Canonical hashes:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
P2.2    633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86
P2.3    15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e
P2.4    78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97
P2.5    292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696
```

P2.5 exact Windows evidence:

```text
mild_loss            0.030140495868
severe_loss          0.073198347107
shallow_survival     0.297520661157
deep_survival        0.787500000000
mild_bank_killed     20
severe_bank_killed   70
recovery_gain        0.024487576856
reactivated          81
repeated_final       0.076970584820
single_severe_final  0.111289229748
```

Fresh-process replay A/B reproduced the same P2.5 aggregate exactly on Godot `4.7.1.stable.double.custom_build.a13da4feb`.

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
P2.5 Disturbance + Recovery ACCEPTED
   ↓
P2.6 Long-Horizon Biogeography ← EXECUTE NOW
   ↓ PASS
P2.7 Lineage Divergence / Speciation Candidate Diagnostics
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

EVO1 final acceptance remains:

`NO_BIOME_SPECIES_TABLES_AND_MULTIPLE_CAUSALLY_EXPLAINABLE_PERSISTENT_COMMUNITIES`.

## P2.5 accepted semantics

P2.5 proves explicit event chronology with independent mechanical and seed-bank pressure channels. Adult damage is delegated to accepted CAL1-D exposure/anchoring mechanics; seed-bank damage conserves integer counts exactly; recovery reuses P2.2 bank reactivation, P2.3 turnover coefficients, ResourceModel and accepted P1 capacity.

The exact Windows run confirms stronger severe than mild damage, stronger survival of the better anchored deep-root lineage, positive recovery after a single severe event, and suppression of recovery by a second event.

## P2.6 scope

P2.6 must integrate already accepted local and spatial semantics rather than replace them.

Target structure:

```text
research patch set
   +
patch-local P2.5 cohort state
   +
repeated P2.4 propagule transfer
   +
patch-specific disturbance chronology
   ↓
long-horizon occupancy history
range expansion
local extinction
recolonization
regional persistence
lineage range filtering
```

P2.6 is a metapopulation orchestrator/observer. It must not introduce a second local growth/turnover model, a species-placement table, or canonical production Spatial/Time fabrics.

Required proof direction for the implementation candidate:

- a source lineage expands to additional patches only through accepted P2.4 propagule routing;
- geographic isolation filters inherited dispersal traits;
- a severe local disturbance can remove local adult presence without deleting regional lineage truth;
- later propagule flow and/or surviving bank memory can recolonize the disturbed patch;
- repeated disturbance changes long-horizon occupancy/persistence relative to a no-disturbance control;
- range/occupancy histories are deterministic and bounded;
- all local event and migration ledgers remain conserved;
- no biome/species placement table appears.

## Ownership boundary

P2.6 research patch geometry and year index remain experiment inputs. ECO does not claim canonical Spatial Domain Fabric, Time Fabric, Environment event generation, World Lifecycle, Work Budget, persistence, authority or networking.

Current resolver: `IMPLEMENT EVO1/P2.6 LONG-HORIZON BIOGEOGRAPHY`.
