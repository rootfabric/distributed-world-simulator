# ECO.EVO1 / P2.6 — Long-Horizon Biogeography — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `9aa4678e9be99556fb54057f6580f219325c0126`.

Parent: `ECO.EVO1/P2.5 ACCEPTED`, aggregate `292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696`.

## Purpose

P2.6 is the first long-horizon regional/metapopulation layer. It does not replace local ecology. Instead it orchestrates accepted patch-local cohort state across time and space:

```text
P2.5 local adult + seed-bank state
        +
P2.4 coordinate propagule routing
        +
patch-local P2.5 disturbance events
        +
accepted P2.5 annual recovery/turnover
        ↓
regional occupancy history
colonization / local extinction / recolonization
range persistence diagnostics
```

No biome/species placement table participates.

## Research topology

The controlled experiment uses the already proven P2.4 mainland/island geometry:

```text
SOURCE Rect2(-10,-10,20,20)
NEAR   Rect2(11,-20,24,40)
FAR    Rect2(50,-40,80,80)
```

Patch geometry remains a research input only and does not claim canonical Spatial Domain Fabric ownership.

Only `SOURCE` is a propagule source in the controlled run. This deliberately models a stable mainland reservoir feeding two islands while island-local state evolves through accepted P2.5 semantics.

## Causal lineages

Two inherited strategies are tracked:

```text
PERSISTENT_SHORT
  height 1.6 m
  root depth 1.2 m
  dispersal 5 m
  high dormancy / longer bank

FRAGILE_LONG
  height 3.0 m
  root depth 0.05 m
  dispersal 20 m
  lower dormancy / shorter bank
```

The broad disperser can reach the isolated FAR patch more persistently. Its tall/shallow morphology also makes it mechanically vulnerable under accepted CAL1-D disturbance mechanics. This is a trade-off, not a hardcoded winner rule.

## Thirty-year chronology

```text
years 1..14   eastward transport
years 15..18  westward transport + four FAR severe events
years 19..30  eastward transport restored
```

The FAR events use the accepted P2.5 contract:

```text
mechanical_severity = 1.0
seed_bank_mortality_fraction = 1.0
```

Migration happens before a same-year disturbance, so immigrants arriving during an event year receive the same local event pressure. There is no hidden post-event rescue bonus.

A no-disturbance control receives the exact same transport chronology.

## Required evidence

The exact Windows candidate gate requires:

- accepted P2.5 parent hash unchanged;
- FAR colonization by the long lineage before year 15;
- local FAR adult extinction of that lineage during the disturbance interval;
- later FAR recolonization after eastward transport resumes;
- no corresponding post-year-14 FAR extinction in the no-disturbance control;
- regional long-lineage adult presence never falls to zero while FAR goes locally extinct;
- FAR is reoccupied by the long lineage at year 30;
- disturbance creates more FAR absence than the identical-transport control;
- long-disperser FAR patch-years exceed short-disperser FAR patch-years;
- long-disperser regional patch-years exceed short-disperser patch-years;
- all P2.4 migration ledgers conserve;
- all P2.5 event ledgers conserve;
- adult and seed-bank cohort counts remain bounded;
- same-process and fresh-process aggregate hashes match exactly.

Local adult occupancy uses the accepted P2.3 `EXTINCTION_BIOMASS_KG_M2` threshold by reference; P2.6 does not invent a second extinction threshold.

## Implementation boundary

`22bad1fcc9302c03a52eee5585691192ebd6e37b -> 9aa4678e9be99556fb54057f6580f219325c0126` adds exactly five files:

- `scripts/research/ecology/plant_long_horizon_biogeography_v1.gd`;
- `scripts/research/ecology/plant_long_horizon_biogeography_experiment_v1.gd`;
- `tests/research/ecology/eco_evo1_p2_6_long_horizon_biogeography_acceptance.gd`;
- `tests/research/ecology/eco_evo1_p2_6_restart_replay_probe.gd`;
- `RUN_ECO_EVO1_P2_6_TESTS.ps1`.

Accepted P2.5/P2.4/P2.3/P2.2/P2.1/CAL1 sources and runtime paths are unchanged.

## Strict P2.7 boundary

P2.6 tracks inherited lineages and their geographic histories but does not declare species, reproductive isolation, divergence thresholds or speciation candidates. Those begin in P2.7.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_6_TESTS.ps1 -GodotPath $Godot
```

The runner performs parser/preload `--check-only` before the long accepted P2.5 parent regression.

Until PASS:

```text
P2.6 = IMPLEMENTED_CANDIDATE
P2.6 != ACCEPTED
P2.7 = BLOCKED
```
