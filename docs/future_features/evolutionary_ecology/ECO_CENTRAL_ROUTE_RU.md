# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.8 REPAIRED CANDIDATE / EXACT WINDOWS RERUN`.

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

## Current route

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
P2.8 Deterministic Save/Restart Plant World Proof
   ├─ original candidate 8cd4c440... → exact Windows FAIL
   ├─ finding P2_8_CODEC_001_JSON_NUMBER_VARIANT_ERASURE
   ├─ codec repair dc910baa...
   ├─ codec preflight 31fd42a...
   └─ fail-fast runner 8d5de417... ← CURRENT REPAIRED CANDIDATE
        ↓ exact Windows PASS required
EVO1 COMPLETE
   ↓
post-EVO1 route resolution: EVO2 + XFER0
```

## What the exact Windows log proved

The first P2.8 candidate run used Godot `4.7.1.stable.double.custom_build.a13da4feb`.

Before P2.8 execution it repeated the full accepted parent chain. P2.1 through P2.7 all passed again with their accepted hashes. P2.7 again produced:

`7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`.

P2.8 parser/preload also passed. The first P2.8 assertion then failed:

```text
ECO.EVO1-P2.8 assertion failed: experiment result exists
```

Thus the failure was isolated to `Experiment.run()` and was not a regression in P2.7-or-earlier ecology.

## Root cause

Original P2.8 typed JSON handled `Vector2`, `Rect2`, `StringName` and packed strings explicitly, but emitted integer Variant values as ordinary JSON numbers.

Direct execution on the project-attached Godot Linux double build with the same engine commit proved:

```text
before JSON: int -> TYPE_INT
JSON.parse_string: same numeric value -> TYPE_FLOAT
```

P2.8 canonical hashing intentionally distinguishes:

```text
TYPE_INT   -> I...
TYPE_FLOAT -> F...
```

Therefore a newly serialized checkpoint could change `current_year`, `seed_count`, counters and other integer truth from TYPE_INT to TYPE_FLOAT during parse, causing its own `world_hash` / `checkpoint_hash` verification to fail closed.

Finding:

`P2_8_CODEC_001_JSON_NUMBER_VARIANT_ERASURE`.

## Repair

`dc910baa78c5b68f606210a7bd60fe9e5cc0d4f1` changes only the P2.8 persistence codec:

```text
TYPE_INT
  -> typed Int JSON wrapper
  -> int(value) during decode
```

Diff from original candidate for the semantic repair itself is one P2.8 file, `+5/-1`. No accepted P2.7-or-earlier source and no runtime path changed.

`31fd42a503875247cc758b36d7915a99a6a72698` adds a dedicated checkpoint codec regression. It verifies nested integer/float types, `Vector2`, `Rect2`, `PackedStringArray` and exact canonical value hash across JSON round-trip.

`8d5de417f83ac257ee3bc1ae40c02847ac82de82` moves that regression before the long parent chain in the P2.8 runner.

## Supplementary same-engine verification

The attached Linux binary reports the exact same engine source revision:

`4.7.1.stable.double.custom_build.a13da4feb`.

On it, repaired codec probe reproduced the same canonical hash before and after JSON round-trip:

`563208df7930f3ca9e341076c9dbe23f71c59d559f9206d615b164fb981cbab1`.

A two-cut representative checkpoint flow was then run in three fresh Godot processes. Every run produced:

```text
cut A year 14
checkpoint A = e10eed0d6979e4f0f3ed605a3d1a53c8688d3638fc5dc8aa586fe124c6724e41

cut B year 18
checkpoint B = 52fe07c45258cef3f90e03aaed65d1e5ad35bad8be77defb3ad1de01848845e4

final year = 30
P2.7 evidence preserved = true
tamper rejected = true
```

This is supplementary evidence, not a substitute for exact Windows canonical acceptance.

## P2.8 final proof still required

P2.8 must still establish the full semantic equality:

```text
P2.6-equivalent baseline result_hash
  == stateful uninterrupted result_hash
  == save14/restore/save18/restore result_hash
```

plus exact final cohort state, persisted P2.7 diagnostics, conservation and fresh-process disk restore A/B.

## Exact Windows rerun

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_8_TESTS.ps1 -GodotPath $Godot
```

Runner is now fail-fast:

```text
parser/preload preflight
P2.8 checkpoint codec preflight
accepted P2.7 full regression
P2.8 acceptance / disk checkpoint creation
fresh process replay A
fresh process replay B
aggregate + P2.6 result equality
```

Until exact Windows PASS:

```text
P2.8 = REPAIRED_CANDIDATE
P2.8 != ACCEPTED
EVO1 != COMPLETE
EVO2 = BLOCKED
```

Current resolver: `RERUN EVO1/P2.8 EXACT WINDOWS AFTER CHECKPOINT CODEC REPAIR`.
