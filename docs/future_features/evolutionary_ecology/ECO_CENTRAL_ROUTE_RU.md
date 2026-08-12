# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.8 AUTHORIZED`.

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
ECO.EVO1 / P2.6           ACCEPTED
ECO.EVO1 / P2.7           ACCEPTED
```

Canonical hashes:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
P2.2    633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86
P2.3    15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e
P2.4    78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97
P2.5    292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696
P2.6    3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
P2.7    7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe
```

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
P2.6 Long-Horizon Biogeography ACCEPTED
   ↓
P2.7 Lineage Divergence / Speciation Candidate Diagnostics ACCEPTED
   ↓
P2.8 Deterministic Save/Restart Plant World Proof ← CURRENT
```

## P2.7 accepted result

Exact Windows Godot `4.7.1.stable.double.custom_build.a13da4feb` produced:

```text
aggregate_hash=7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe
candidate=true
connected=false
similar=false
recent=false
split_age=25
isolation=1.0
connection=0.0
genome=0.473241998529
ecology=0.130666666667
```

Both fresh-process probes reproduced the exact aggregate. P2.7 therefore establishes a deterministic, falsifiable divergence-diagnostic layer while keeping `canonical_species_declared=false`.

## P2.8 objective

P2.8 is the final EVO1 proof. It must establish that a complete autonomous Plant World state can cross a process boundary without changing ecology semantics.

The proof must preserve and validate:

```text
absolute simulation year
patch definitions + environments
adult cohort truth
seed-bank cohort truth
strategies / genome + recruitment checksums
source patch set
transport schedule
future disturbance schedule
regional history and transition history
migration/disturbance accounting
lineage ancestry + divergence observations/diagnostics
```

The canonical comparison is:

```text
uninterrupted run 1..30
        ==
run 1..K -> serialize -> validate -> deserialize in fresh process -> continue K+1..30
```

Deterministic event/reproduction keys must continue to use absolute year. Restart is not allowed to reset time to year 1 or regenerate ecology from presentation/biome labels.

P2.8 remains research persistence semantics only. It does not claim production persistence durability, transactions, authority or canonical Time/Spatial ownership.

Current resolver: `IMPLEMENT EVO1/P2.8 DETERMINISTIC SAVE/RESTART PLANT WORLD PROOF`.
