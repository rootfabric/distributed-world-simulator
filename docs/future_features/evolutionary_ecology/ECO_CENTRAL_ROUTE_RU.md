# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.7 IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

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
P2.7 Lineage Divergence / Speciation Candidate Diagnostics ← CURRENT CANDIDATE
   ↓ PASS
P2.8 Deterministic Save/Restart Plant World Proof
```

## P2.7 implementation

Implementation head: `8da9c039a8591d61a0d542aa4e4695a51a9d20d6`.

P2.7 adds a **diagnostic-only** lineage evidence contract. It does not create species taxonomy and does not simulate a mutation trajectory tuned to a desired endpoint.

### Evidence dimensions remain separate

```text
shared ancestry
split age
spatial isolation
connection history
genome distance
recruitment-trait distance
ecological-history distance
```

There is no weighted scalar `speciation score` or combined fitness. The research candidate flag is a conjunction of explicit gates:

```text
split age >= 12 y
isolation fraction >= 0.75
connection fraction <= 0.10
genome distance >= 0.18
ecological-history distance >= 0.10
shared ancestry required
```

These thresholds are candidate-detection policy, not a universal species definition.

### Controlled falsification matrix

```text
ISOLATED + DIVERGED
  -> candidate=true

DIVERGED + CONNECTED
  -> candidate=false

ISOLATED + SIMILAR
  -> candidate=false

RECENT + DIVERGED + ISOLATED
  -> candidate=false
```

This prevents geography alone, genome distance alone or a recent dramatic phenotype contrast from being mistaken for speciation evidence.

Every positive candidate still exports:

`canonical_species_declared=false`.

The kernel contains no `species_id` assignment, no biome lookup and no species placement table.

### Implementation boundary

`a47127b09dde280525bf5e076b8e3a99d8a7d9a9 -> 8da9c039a8591d61a0d542aa4e4695a51a9d20d6` is one commit adding exactly five P2.7 research/test files. Accepted P2.6-or-earlier sources and runtime paths are unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_7_TESTS.ps1 -GodotPath $Godot
```

The gate is fail-closed: parser/preload preflight -> full accepted P2.6 regression -> P2.7 acceptance -> two fresh-process replay probes.

Until PASS:

```text
P2.7 = IMPLEMENTED_CANDIDATE
P2.7 != ACCEPTED
P2.8 = BLOCKED
```

Current resolver: `RUN EVO1/P2.7 EXACT WINDOWS LINEAGE DIVERGENCE DIAGNOSTICS GATE`.
