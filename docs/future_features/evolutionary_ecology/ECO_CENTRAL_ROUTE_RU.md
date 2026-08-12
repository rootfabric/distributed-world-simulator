# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.7 READY`.

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
```

## P2.6 accepted proof

Exact Windows / Godot `4.7.1.stable.double.custom_build.a13da4feb` produced:

```text
colonized=1
extinct=18
recolonized=19
control_extinction=-1
long_patch_years=90
short_patch_years=61
far_long=29
far_short=0
event_absence=1
control_absence=0
final_reoccupied=true
regional_persist=true
```

Two fresh processes reproduced exact aggregate `3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c`.

Thus the accepted regional ecology can express `colonization -> local extinction -> recolonization` while the lineage persists elsewhere, without biome/species placement rules.

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
P2.7 Lineage Divergence / Speciation Candidate Diagnostics ← CURRENT
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

## P2.7 boundary

P2.7 is a diagnostic layer over lineage evidence. It may consume:

- ancestry/split chronology;
- inherited PlantGenome and recruitment traits;
- P2.6 geographic occupancy history;
- ecological-history summaries;
- evidence of continued connectivity/gene-flow opportunity.

It must expose the dimensions separately rather than hide them in one fitness score. A `SPECIATION_CANDIDATE` marker is only a research flag requiring convergent evidence. It is explicitly **not** a canonical species declaration and cannot create or place a `species_id`.

Required controls must distinguish at least:

1. isolated + substantially diverged lineage pair -> candidate;
2. substantially diverged but still connected pair -> not candidate;
3. isolated but only weakly diverged pair -> not candidate;
4. recent/near-identical pair -> not candidate.

The detector therefore cannot reduce speciation to distance alone, isolation alone, biome membership, or an arbitrary species table.

P2.8 remains blocked until P2.7 exact-Windows acceptance.
