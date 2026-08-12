# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.3 REPAIRED CANDIDATE / EXACT WINDOWS RE-RUN`.

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

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
P2.1 Seed Dispersal Kernel ACCEPTED
   ↓
P2.2 Establishment / Recruitment / Seed Bank ACCEPTED
   ↓
P2.3 Local Population Turnover + Succession ← REPAIRED CANDIDATE
   ↓ PASS
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

## P2.3 implementation and parser repair

Implementation origin: `b8d6553df911a4eca9765509c018987fe9f5cd4b`.

Initial candidate control: `39ceac4412f284fb263ee100df6ad223b9780d53`.

Exact Windows finding:

```text
Parse Error: The member "Engine" shadows a native class.
```

Repair head: `87c7838f9d476735ef92db0d662290b58861cd56`.

The repair changes only the preload alias in `plant_local_population_succession_experiment_v1.gd`:

```text
Engine -> PopulationEngine
```

No ecological formula, control strategy, threshold, accepted parent, runtime path or P2.4 boundary changed.

### Local adult cohort state

P2.3 uses bounded lineage/age cohorts with biomass and ancestry identity. Recruitment cohorts are merged by lineage/year instead of becoming one entity per plant.

### Turnover and local density

Annual adult survival has explicit lifespan and resource-stress terms. Productive net balance drives vegetative growth. The implementation reuses the existing P1 `0.24` stress-mortality and `0.20` vegetative-growth research coefficients and the accepted single-patch capacity `8.0 kg/m²` rather than creating a second capacity model.

### Persistent history

P2.2 seed banks are advanced every year. Their reactivation feeds new adult cohorts. Mature lineage aggregates also reproduce through:

```text
CAL1-D lifecycle seed output
  -> P2.1 dispersal
  -> P2.2 establishment/seed bank
  -> P2.3 local adults
```

### Succession control

The controlled run starts with two causal life histories:

- EARLY: fast growth, short lifespan, low dormancy, low shade tolerance;
- BANKED: slower growth, long lifespan, high dormancy/long seed bank, high shade tolerance.

Both start under open light. At year 4 the succession run enters deep shade; an open control does not. Acceptance still requires EARLY to lead initially, BANKED to gain after transition, and BANKED final share to be higher under shade history than open control.

### Strict P2.4 boundary

Outside-domain seeds are counted as export but never inserted into a second patch. No neighbour graph, colonization topology or migration routing exists in P2.3.

## Exact Windows re-run

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_3_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
P2.3 = REPAIRED_IMPLEMENTED_CANDIDATE
P2.3 != ACCEPTED
P2.4 = BLOCKED
```

Current resolver: `RE-RUN EVO1/P2.3 EXACT WINDOWS LOCAL POPULATION TURNOVER + SUCCESSION GATE`.
