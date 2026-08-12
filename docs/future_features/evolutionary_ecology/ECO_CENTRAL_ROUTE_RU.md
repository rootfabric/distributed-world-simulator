# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.6 IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

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
P2.6 Long-Horizon Biogeography ← CURRENT CANDIDATE
   ↓ PASS
P2.7 Lineage Divergence / Speciation Candidate Diagnostics
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

EVO1 final acceptance remains:

`NO_BIOME_SPECIES_TABLES_AND_MULTIPLE_CAUSALLY_EXPLAINABLE_PERSISTENT_COMMUNITIES`.

## P2.6 implementation

Implementation head: `9aa4678e9be99556fb54057f6580f219325c0126`.

Diff from accepted P2.5 adds exactly five ECO research/test files and modifies no accepted P2.5/P2.4/P2.3/P2.2/P2.1/CAL1 source or runtime path.

### Regional composition, not a second local ecology

P2.6 is a metapopulation orchestrator. Patch-local annual ecology still runs through accepted `DisturbanceRecovery.advance_year`; event response still runs through accepted `DisturbanceRecovery.apply_event`; inter-patch propagules still run through accepted `PatchMigration.migrate_reproduction_event`.

Local adult occupancy is evaluated with the accepted P2.3 `EXTINCTION_BIOMASS_KG_M2` threshold by reference.

### Controlled thirty-year history

Research geography reuses P2.4 SOURCE / NEAR / FAR patches. Only SOURCE is the propagule reservoir.

Two causal strategies are tracked:

```text
PERSISTENT_SHORT  1.6m height / 1.2m roots / 5m dispersal / long bank
FRAGILE_LONG      3.0m height / 0.05m roots / 20m dispersal / shorter bank
```

Chronology:

```text
y1..14   east transport
y15..18  west transport
          + FAR mechanical=1.0 / bank mortality=1.0 each year
y19..30  east transport restored
```

A no-disturbance control uses the same transport schedule. Migration is applied before same-year disturbance, so event-year immigrants receive the same damage pressure rather than bypassing it.

The gate requires a complete biogeographic cycle for the broad disperser:

```text
regional persistence
      +
FAR colonization
      ↓
local FAR adult extinction during disturbance/isolation interval
      ↓
FAR recolonization after transport recovery
```

It also requires FAR and regional patch-year filtering toward the broader disperser, exact migration/event conservation, bounded cohort counts and deterministic replay.

### Ownership boundary

Patch geometry, year index and transport history remain research experiment inputs. P2.6 does not claim canonical Spatial Domain Fabric, Time Fabric, Environment simulation/event generation, World Lifecycle, Work Budget, persistence, authority or networking.

### Strict P2.7 boundary

P2.6 records lineage range histories only. It does not define species, reproductive isolation, divergence thresholds or speciation verdicts. P2.7 owns those diagnostics.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_6_TESTS.ps1 -GodotPath $Godot
```

The runner performs parser/preload `--check-only`, then the full accepted P2.5 parent regression, P2.6 acceptance and two fresh-process replay probes.

Until PASS:

```text
P2.6 = IMPLEMENTED_CANDIDATE
P2.6 != ACCEPTED
P2.7 = BLOCKED
```

Current resolver: `RUN EVO1/P2.6 EXACT WINDOWS LONG-HORIZON BIOGEOGRAPHY GATE`.
