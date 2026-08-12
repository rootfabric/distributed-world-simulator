# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.2 IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

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

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
P2.1 Seed Dispersal Kernel ACCEPTED
   ↓
P2.2 Establishment / Recruitment / Seed Bank ← CURRENT CANDIDATE
   ↓ PASS
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

## P2.2 implementation

Implementation head: `d09857528adee1010f2177095f2afb04bf651532`.

Implementation diff from accepted P2.1 adds exactly six ECO files and modifies no accepted P2.1/CAL1 source or runtime path.

### Cohort transition

P2.2 consumes an inside-domain P2.1 seed packet and resolves it into integer cohort counts:

```text
input
= exported
+ decayed
+ failed after germination
+ recruited
+ remaining seed bank
```

Outside-domain P2.1 packets remain export and bypass local establishment.

### Recruitment traits

A sidecar trait contract adds `dormancy_fraction` and `seed_bank_half_life_years` without changing the accepted plant genome schema. Defaults are research defaults, not empirical calibration.

### Germination

Seed-stage water matching uses inherited water preference/tolerance but deliberately does not grant adult root-depth moisture access. Germination activation combines seed water response and temperature, then dormancy reduces immediate activation.

### Establishment

Post-germination establishment separately combines accepted light response, nutrient response and flood survival. No biome name, species name or habitat lookup participates.

### Seed bank

Viability follows half-life decay. Nongerminated viable seeds remain explicit seed-bank cohorts with age and identity. The bank can later reactivate when environment improves.

### P2.3 boundary

P2.2 does not update adult population biomass, carrying-capacity competition, succession, repeated reproductive cycles or regional migration. Those begin at P2.3+.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_2_TESTS.ps1 -GodotPath $Godot
```

Required evidence includes:

- exact accepted P2.1 parent;
- conservation in every controlled case;
- favourable > dry and favourable > flooded recruitment;
- low dormancy increases immediate recruitment;
- high dormancy increases bank size;
- long half-life retains more bank after two years;
- bank reactivation produces recruitment after improvement;
- outside-domain 80-seed control remains export-only;
- cohort counts stay bounded by packet outcomes;
- lineage/genome/event identity survives;
- same/fresh-process aggregate equality.

Until PASS:

```text
P2.2 = IMPLEMENTED_CANDIDATE
P2.2 != ACCEPTED
P2.3 = BLOCKED
```

## Global boundary

Standalone EVO remains research-only. ECO owns ecology semantics, not canonical spatial/weather/runtime foundations. `XFER1/LIVE` remain deferred until global contracts exist.

Current resolver: `RUN EVO1/P2.2 EXACT WINDOWS ESTABLISHMENT / RECRUITMENT / SEED BANK GATE`.
