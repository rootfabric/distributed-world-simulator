# FABRIC BRIDGE-3 — RESEARCH EXACT CLOSED

Runtime subject: `cf6730c48f6147243a5c99ebb48c19e09fb3093f` / TREE `13e38426a84d55ac7faac06c4eec05ae15a84139`.
Godot: `4.7.1.stable.double.custom_build.a13da4feb`; SHA-256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
Final fresh import: PASS, exit 0, fatal 0.

## A–G

| Stage | Assertions / replay | Result |
|---|---:|---|
| A lifecycle / one writer | 29 | PASS ×2 |
| B FULL → BAKE | 19 | PASS ×2 |
| C bounded LOCAL UNBAKE | 31 | PASS ×2 |
| D continuity / conservation | 539 | PASS ×2 |
| E mutation → fence → rebake | 536 | PASS ×2 |
| F restart / exactly once | 38 | PASS ×2 |
| G 500 / 1000 / 2000 | 25 + 18 + 18 | PASS ×2 |

Total: **1253 assertions per replay**.

Deterministic hashes are identical between replay #1 and #2:

```text
A=36d2da80dc6adda6f4ad998c2fd011add99dc8f718c9b1678f994d4f3cc72c30
B=f65fcb1550c9853693776a2c700e0acc3bd4706555e4b679139b314ae0727daf
C=813418ac63009b3e31bdc9a7e52b086557ddb96e962444c2e4e36bdf3c45a478
D=f1ab405d6c4829633d7934e456b2ecc37b5a4cff48d7b0184b759e6f46371f87
E=20acdd3b7789a21ab4699f9de1613b62aea0d06255bd498c5032e443ec7135c4
F=7eda96e277ef650f1f773630439502f095e666521378c0e740b577687d67aadb
F_CAPSULE=8f51c2eab36564a4f6060709fe582fc09ad7c1f09306063899454d9234e307fb
G=66eebb542071bc5e3786c5029ba75d96e6492a117b89585ed8e8ae15b8136984
CLOSURE=4f9ec661e99775d0afc85995d51a4d614158414fc760141daffe0dab1b25f4a4
```

## Lifecycle proved

`FULL → STRUCTURAL_BAKE → certified guard → LOCAL_FULL → external canonical topology mutation → old-writer fence → settle → two fresh REBAKED components`.

Prepare never publishes a second owner. Stale writer tokens are fenced. LOCAL UNBAKE materializes exactly 20 parts and keeps two residual bodies reduced. D checks all 500 parts against the predecessor reconstruction oracle plus boundary/mass/momentum/energy continuity. E never mints canonical damage: it consumes an external canonical break and rejects premature rebake. F proves restart at FULL, BAKE, LOCAL_FULL, mutation-fenced and REBAKED phases; corrupt/stale capsules are rejected and event history remains exactly once.

## Scale

| Parts | FULL at event | Residual | Final baked | Reconstructed | Local rebake validations | Global rebuilds | Duplicate owners |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 500 | 20 | 2 | 2 | 20 | 20 | 0 | 0 |
| 1000 | 20 | 2 | 2 | 20 | 20 | 0 | 0 |
| 2000 | 20 | 2 | 2 | 20 | 20 | 0 | 0 |

500 additionally checks FULL/reference parity; maximum error `2.1316282072803e-14`, under `1e-8`.

## Regression / scope

Fresh current checks: B0.6 A-D PASS; BRIDGE-2 closure 122+125 PASS; COMPLEX2-CLOSE 44 PASS including PERF hash; B0.5-P0 63 PASS. B0.6-E smoke+500 passed; its 1000/2000 and B0.5-A use prior exact-closed evidence because Git compare from B0.6 closure to the BRIDGE-3 subject contains only new BRIDGE-3 paths and no predecessor runtime/test changes.

This is research exact closure, not main checkpoint acceptance or production merge. COMPLEX3 may now open as the next research line.
