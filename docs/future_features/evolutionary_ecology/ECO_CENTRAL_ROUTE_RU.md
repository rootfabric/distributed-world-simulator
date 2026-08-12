# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.8 IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

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
P2.7 Lineage Divergence / Speciation Candidate Diagnostics ACCEPTED
   ↓
P2.8 Deterministic Save/Restart Plant World Proof ← CURRENT CANDIDATE
   ↓ PASS
EVO1 COMPLETE
   ↓
post-EVO1 route resolution: EVO2 + XFER0
```

## P2.8 implementation

Implementation head: `f7147082e0ca1e8913885b8ad47d76dc9b086416`.

P2.8 introduces a research-only typed checkpoint for the complete Plant World state. It does not change accepted P2.7/P2.6 ecology mechanics.

### Strong semantic equivalence gate

The new stateful persistence driver mirrors accepted P2.6 annual orchestration using accepted helpers/contracts. Before testing restart it must reproduce the exact uninterrupted P2.6 `result_hash` for the same 30-year disturbed mainland/near/far scenario.

Then the same world follows:

```text
0 -> 14 -> SAVE A -> RESTORE -> 18 -> SAVE B -> RESTORE -> 30
```

and must end with exactly the same:

- P2.6 result hash;
- final adult/seed-bank state hash;
- migration and disturbance conservation;
- P2.7 divergence-diagnostic payload hash.

### Why years 14 and 18

Cut A occurs before years 15..18 westward transport + severe FAR events. Therefore future schedules must survive serialization.

Cut B occurs after all severe events but before eastward transport resumes at year 19. Therefore accumulated event/history truth must survive serialization.

Absolute `current_year` is persisted. Deterministic emission/reproduction/event keys never restart at year 1.

### Checkpoint integrity

The checkpoint has typed JSON encoding for Godot values plus:

```text
world_hash
evidence_hash
checkpoint_hash
```

Dictionary hashing is canonical/sorted and serialization uses full float precision. A controlled mutation of the persisted P2.7 evidence hash must be rejected rather than repaired or regenerated.

### Fresh-process gate

Acceptance writes year-14 state to `user://eco_evo1_p2_8_plant_world_checkpoint.json`.

Fresh process A and B independently read that file, continue through year 18, serialize/restore again, finish year 30 and must reproduce the exact acceptance aggregate and result hash.

### Ownership boundary

This is research persistence semantics, not production persistence infrastructure. No claim is made over durability backend, transactions, authority, networking, canonical Time Fabric, canonical Spatial Domain Fabric or species taxonomy.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_8_TESTS.ps1 -GodotPath $Godot
```

Runner is fail-closed:

```text
parser/preload preflight
accepted P2.7 full regression
P2.8 acceptance / disk checkpoint creation
fresh process replay A
fresh process replay B
aggregate + P2.6 result equality
```

Until PASS:

```text
P2.8 = IMPLEMENTED_CANDIDATE
P2.8 != ACCEPTED
EVO1 != COMPLETE
EVO2 = BLOCKED
```

Current resolver: `RUN EVO1/P2.8 EXACT WINDOWS DETERMINISTIC SAVE/RESTART PLANT WORLD GATE`.
