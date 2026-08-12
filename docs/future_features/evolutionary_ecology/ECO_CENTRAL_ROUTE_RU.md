# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.5 IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

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
P2.5 Disturbance + Recovery ← CURRENT CANDIDATE
   ↓ PASS
P2.6 Long-Horizon Biogeography
   ↓
P2.7 Lineage Divergence / Speciation Candidate Diagnostics
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

EVO1 final acceptance remains:

`NO_BIOME_SPECIES_TABLES_AND_MULTIPLE_CAUSALLY_EXPLAINABLE_PERSISTENT_COMMUNITIES`.

## P2.5 implementation

Implementation head: `b645ee451dd5c1c2558647c8e50eb293ec80c21c`.

Diff from accepted P2.4 adds exactly five ECO research/test files and modifies no accepted P2.4/P2.3/P2.2/P2.1/CAL1 source or runtime path.

### Disturbance is an event, not a species modifier

P2.5 event input has two independent channels:

```text
mechanical_severity
seed_bank_mortality_fraction
```

Adult mechanical response is delegated to accepted CAL1-D exposure/anchoring mechanics. Seed-bank mortality is explicit event pressure and maintains exact integer conservation.

### Recovery

Annual recovery advances surviving P2.2 banks through the accepted bank kernel. Recruits re-enter adult cohort truth. Adult background turnover and productive regrowth reference P2.3 `STRESS_MORTALITY_RATE` and `VEGETATIVE_GROWTH_RATE` directly, while capacity remains the accepted P1 patch capacity.

Thus P2.5 does not create a second hidden turnover calibration.

### Controlled chronology

All runs start from the same two-lineage community, equal adult biomass and equal seed-bank counts in the same favourable environment:

```text
CONTROL   no event
MILD      y1 mechanical .35 / bank mortality .10
SEVERE    y1 mechanical .85 / bank mortality .35
REPEATED  SEVERE y1 + y6 mechanical .75 / bank mortality .30
```

`SHALLOW_FAST` is taller/shallow-rooted; `DEEP_BANKED` is shorter/deep-rooted. Acceptance requires CAL1-D mechanical survival to favour the better anchored lineage under the same severe event, while recovery emerges from surviving adults and bank history rather than a recovery bonus.

Required directions include severe loss > mild, severe bank kill > mild, deep survival > shallow, positive recovery after single severe, additional damage from the second event, and repeated final biomass below single-severe final biomass.

### Ownership boundary

P2.5 does not claim canonical disturbance generation, weather/environment event truth, Time Fabric, World Lifecycle, Work Budget, persistence or authority ownership. Its event record is a research input contract for ecology response semantics.

### Strict P2.6 boundary

No long-horizon range map, regional climate-history series, geographic occupancy metric or biogeographic persistence analysis exists yet. P2.6 remains blocked.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_5_TESTS.ps1 -GodotPath $Godot
```

The runner performs parser/preload `--check-only` before the long accepted P2.4 parent regression, then acceptance and two fresh-process replay probes.

Until PASS:

```text
P2.5 = IMPLEMENTED_CANDIDATE
P2.5 != ACCEPTED
P2.6 = BLOCKED
```

Current resolver: `RUN EVO1/P2.5 EXACT WINDOWS DISTURBANCE + RECOVERY GATE`.
