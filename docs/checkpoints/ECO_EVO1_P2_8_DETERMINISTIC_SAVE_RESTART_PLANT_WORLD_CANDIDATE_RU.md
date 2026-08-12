# ECO.EVO1 / P2.8 — Deterministic Save/Restart Plant World Proof — REPAIRED CANDIDATE

Статус: `REPAIRED_CANDIDATE / RESEARCH_ONLY / EXACT WINDOWS CANONICAL RERUN PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `f7147082e0ca1e8913885b8ad47d76dc9b086416`.
Original candidate/control head: `8cd4c44006867c5ee85b6f21f67dc4290c939506`.
Repair head: `8d5de417f83ac257ee3bc1ae40c02847ac82de82`.
Parent: `ECO.EVO1/P2.7 ACCEPTED`, aggregate `7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`.

## Purpose

P2.8 is the final EVO1 Plant World proof: complete plant-world research truth must cross process boundaries and continue to exactly the same future as uninterrupted execution.

The proof remains research-only. It does not claim production persistence ownership, canonical Time/Spatial ownership, networking authority or species taxonomy.

## Persisted truth

Checkpoint stores and integrity-hashes:

```text
absolute current_year + total_years
patch definitions / Rect2 bounds / EnvironmentSample
adult cohorts
seed-bank cohorts
PlantGenome + recruitment traits
source patch set
transport schedule
future disturbance schedule
regional history
transition / migration / disturbance logs
cumulative accounting + conservation flags
previous / ever occupancy maps
P2.7 divergence diagnostic evidence
```

## Double-cut proof

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

Required equality:

```text
P2.6-equivalent baseline result_hash
  == stateful uninterrupted result_hash
  == save14/restore/save18/restore result_hash
```

Final cohort-state hash and P2.7 diagnostic evidence hash must also match exactly.

## First exact Windows attempt — finding

Exact Windows candidate run on Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

passed parser/preload and the complete accepted chain through P2.7. P2.7 again produced:

`7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`.

P2.8 then failed at its first assertion:

```text
ECO.EVO1-P2.8 assertion failed: experiment result exists
```

Classification:

`P2_8_CODEC_001_JSON_NUMBER_VARIANT_ERASURE`.

Godot JSON round-trip restores JSON numbers as `TYPE_FLOAT`. The original P2.8 codec emitted `TYPE_INT` values as untagged JSON numbers. Therefore integer truth such as `current_year` and `seed_count` changed Variant type after parsing. P2.8 canonical hashing intentionally distinguishes integer and float variants, so a freshly serialized checkpoint failed its own `world_hash` / `checkpoint_hash` verification and was rejected fail-closed.

This is a persistence-codec defect, not a P2.7-or-earlier ecology regression.

## Repair

Commit:

`dc910baa78c5b68f606210a7bd60fe9e5cc0d4f1` — `fix(eco): preserve integer variants in P2.8 checkpoints`.

Repair is intentionally narrow:

```text
TYPE_INT
  -> {"__eco_type":"Int","value":n}
  -> int(value) on decode
```

Diff against original candidate: one P2.8 persistence file, `+5/-1`. No biological, population, migration, disturbance or P2.7 diagnostic semantics changed.

Regression hardening:

- `31fd42a503875247cc758b36d7915a99a6a72698` adds `eco_evo1_p2_8_checkpoint_codec_preflight.gd`;
- `8d5de417f83ac257ee3bc1ae40c02847ac82de82` makes the runner execute that codec gate before the long accepted-parent chain.

The preflight verifies integer, float, `Vector2`, `Rect2`, `PackedStringArray`, nested array/dictionary types and exact canonical value hash across JSON round-trip.

## Supplementary attached-engine verification

The project-attached Linux double build reports the same engine revision:

`4.7.1.stable.double.custom_build.a13da4feb`.

Direct engine probe confirmed the original failure mechanism:

```text
original int typeof = TYPE_INT (2)
JSON parsed typeof = TYPE_FLOAT (3)
```

With the repair, nested codec round-trip preserves integer types and canonical hash exactly.

A representative two-cut save/restart probe was executed in three fresh Godot processes:

```text
cut A year = 14
cut A hash = e10eed0d6979e4f0f3ed605a3d1a53c8688d3638fc5dc8aa586fe124c6724e41

cut B year = 18
cut B hash = 52fe07c45258cef3f90e03aaed65d1e5ad35bad8be77defb3ad1de01848845e4

final year = 30
P2.7 evidence preserved = true
tamper rejected = true
```

All three fresh processes reproduced the same hashes. This is supplementary evidence only; exact Windows remains the canonical acceptance gate.

## Exact Windows rerun

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_8_TESTS.ps1 -GodotPath $Godot
```

Runner order is now fail-fast:

```text
parser/preload preflight
P2.8 checkpoint codec preflight
full accepted P2.7 parent regression
P2.8 acceptance + disk checkpoint write
fresh process replay A
fresh process replay B
aggregate/result equality gate
```

Until this exact Windows rerun passes:

```text
P2.8 = REPAIRED_CANDIDATE
P2.8 != ACCEPTED
EVO1 != COMPLETE
EVO2 = BLOCKED
```
