# ECO.EVO1 / P2.8 — Deterministic Save/Restart Plant World Proof — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `f7147082e0ca1e8913885b8ad47d76dc9b086416`.
Parent: `ECO.EVO1/P2.7 ACCEPTED`, aggregate `7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`.

## Purpose

P2.8 is the final EVO1 Plant World proof. It asks one strict question:

> Can the complete research ecology truth cross process boundaries and continue with exactly the same future as uninterrupted execution?

The proof does **not** modify accepted P2.7-or-earlier ecology code and does not claim production persistence ownership.

## Persisted truth

The checkpoint stores and integrity-hashes:

```text
absolute current_year + total_years
patch definitions / Rect2 bounds / EnvironmentSample values
adult cohort arrays
seed-bank cohort arrays
strategies / PlantGenome + recruitment traits
source patch set
transport schedule
future disturbance schedule
regional history
transition log
migration log
disturbance log
cumulative accounting + conservation flags
previous / ever occupancy maps
P2.7 lineage-divergence diagnostic evidence
```

Godot value types required by the research truth (`Vector2`, `Rect2`, arrays/dictionaries and packed string arrays) use an explicit typed JSON envelope. Serialization requests full float precision. A canonical value hash is independent of dictionary iteration order.

## Absolute-time continuation

P2.8 deliberately reuses accepted P2.6 deterministic keys with the **absolute** simulation year. Restart never renumbers continuation to year 1.

The stateful driver is composed from accepted helpers/contracts:

- P2.6 regional summary, occupancy, emission and record hashing;
- P2.4 coordinate migration;
- P2.5 disturbance application and annual patch-local recovery/turnover.

It must first reproduce the exact `Biogeography.result_hash` of an uninterrupted accepted-P2.6-equivalent disturbed run.

## Double-cut proof

The candidate executes:

```text
UNINTERRUPTED
  year 0 ------------------------------> 30

SAVE/RESTART
  year 0 ----> 14
              SAVE A
              RESTORE
              ----> 18
                   SAVE B
                   RESTORE
                   ---------------------> 30
```

Cut A is immediately before the transport reversal + severe FAR disturbance window. Cut B is after all four severe events and before eastward transport resumes. Thus the proof crosses both future scheduled events and already accumulated event/history state.

Required equality:

```text
P2.6 baseline result_hash
  == stateful uninterrupted result_hash
  == save14/restore/save18/restore result_hash
```

The final cohort-state hash and persisted P2.7 diagnostics hash must also match exactly.

## Fresh-process proof

The acceptance process writes Cut A to:

`user://eco_evo1_p2_8_plant_world_checkpoint.json`.

Two separate headless Godot processes then load that disk checkpoint, advance to Cut B, serialize/restore again, continue to year 30 and must reproduce the same P2.8 aggregate and final P2.6 result hash.

## Fail-closed integrity

Checkpoint envelope contains:

```text
world_hash
evidence_hash
checkpoint_hash
```

The controlled gate mutates the accepted P2.7 hash inside an otherwise JSON-valid checkpoint and requires restore rejection. Corrupted evidence is not silently accepted or regenerated.

## Boundaries

P2.8 is a research persistence/state-transfer proof only. It does not claim:

- production durability or storage backend;
- transaction semantics;
- authority or networking policy;
- canonical Time Fabric / Spatial Domain ownership;
- canonical species taxonomy.

It does not regenerate ecology from biome labels or presentation state.

## Implementation boundary

`f55d87a5bd5c45f98bbcb1180e73429b65f3b162 -> f7147082e0ca1e8913885b8ad47d76dc9b086416` is one commit adding exactly five files:

- `scripts/research/ecology/plant_world_persistence_v1.gd`;
- `scripts/research/ecology/plant_world_save_restart_experiment_v1.gd`;
- `tests/research/ecology/eco_evo1_p2_8_save_restart_acceptance.gd`;
- `tests/research/ecology/eco_evo1_p2_8_restart_replay_probe.gd`;
- `RUN_ECO_EVO1_P2_8_TESTS.ps1`.

Accepted P2.7-or-earlier source and runtime paths are unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_8_TESTS.ps1 -GodotPath $Godot
```

Runner order:

```text
parser/preload preflight
full accepted P2.7 parent regression
P2.8 acceptance + disk checkpoint write
fresh process replay A
fresh process replay B
exact aggregate/result equality gate
```

Until PASS:

```text
P2.8 = IMPLEMENTED_CANDIDATE
P2.8 != ACCEPTED
EVO1 != COMPLETE
EVO2 = BLOCKED
```
