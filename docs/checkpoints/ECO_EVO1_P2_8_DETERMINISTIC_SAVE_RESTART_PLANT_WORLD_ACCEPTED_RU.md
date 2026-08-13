# ECO.EVO1 / P2.8 — Deterministic Save/Restart Plant World Proof — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL / EVO1 COMPLETE`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `f7147082e0ca1e8913885b8ad47d76dc9b086416`.
Acceptance source/control head: `1a0366d293b7b686c0e4adcb13f4ad44645e64ee`.
Parent P2.7 aggregate: `7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`.

P2.8 является финальным gate EVO1. Полный canonical runner после codec repairs прошёл; тем самым EVO1 закрыт как законченный research foundation.

## Exact Windows canonical evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Runner: `RUN_ECO_EVO1_P2_8_TESTS.ps1`.

```text
ECO.EVO1-P2.8 Codec Preflight: PASS (25 assertions)
value_hash=d39b60931c5c3a69102897af57e28555de6cdd9bf00cd035d06540afd5a4da44
bytes=1174

ECO.EVO1-P2.8 Failure Stage Probe: PASS

ECO.EVO1-P2.8 Deterministic Save/Restart Plant World Proof: PASS (32 assertions)
aggregate_hash=ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
p2_7=7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe
baseline=06c100622794fdb4153ec93f0d341b90fb76c21e57be06faab8bb81ca3129d4d
resumed=06c100622794fdb4153ec93f0d341b90fb76c21e57be06faab8bb81ca3129d4d
final_state=50ca2aca3acd98d54eaff88cc709db12094a8b2cec33a97762680526d55e2345
diagnostics=b76b0afda1b4fdf298313934d4cb5bd06764a3959f8c599bc163eb2953495c79
tamper_rejected=true
cuts=14,18
total_years=30

ECO.EVO1-P2.8 candidate automated gates: PASS
```

Checkpoint A:

```text
year=14
world_hash=e907052c74c3996a6c2eb9864b3e03940de355ea649a55dfb32baa201b7c8c65
serialized_bytes=84465
checkpoint_hash=827a13fa52c80569d37bbabe744cd8c41e6e192c5ab64ff4d88779ad4ccfa7fd
```

Checkpoint B:

```text
year=18
world_hash=75e968b042e1e8271b22f051061ec7d32ae4bf6f90e172e0036a26b49bbb0f19
serialized_bytes=99365
checkpoint_hash=bd177a95662a7e80c11881163178c555d7704b5035abcac6fa85a1e577359915
```

Fresh-process replay A и B прошли по 10 assertions и воспроизвели те же aggregate/result/checkpoint/final-state hashes.

Полная parent regression PH3 -> PH3C -> CAL1-A..F -> P2.1..P2.7 также прошла в составе canonical runner. Последние parent identities:

```text
P2.5=292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696
P2.6=3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
P2.7=7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe
```

## Closed codec findings

`P2_8_CODEC_001_JSON_NUMBER_VARIANT_ERASURE` закрыт explicit `TYPE_INT` wrapper.

`P2_8_CODEC_002_JSON_DOUBLE_PRECISION_ERASURE` закрыт exact Variant-byte codec для `TYPE_FLOAT`, `Vector2` и `Rect2`:

```text
Variant -> var_to_bytes -> base64 -> JSON -> base64 -> bytes_to_var -> exact Variant
```

Эти repairs не меняют biology/population semantics и accepted P2.7-or-earlier ecology sources.

## Targeted Linux corroboration

На Linux тем же Godot build `4.7.1.stable.double.custom_build.a13da4feb` отдельно воспроизведён **только codec preflight**, не полный repository suite:

```text
TARGETED_CODEC_PREFLIGHT
PASS (25 assertions)
value_hash=d39b60931c5c3a69102897af57e28555de6cdd9bf00cd035d06540afd5a4da44
bytes=1174
fresh processes A/B/C: identical
```

Эта Linux запись является дополнительным cross-platform codec evidence и не подменяет exact-Windows canonical acceptance.

## Accepted meaning

P2.8 доказывает, что research plant-world truth может быть сериализована, проверена, восстановлена в fresh process и продолжена с absolute simulation time без изменения будущих deterministic keys и результата. Persisted truth включает patch/environment geometry, adult и seed-bank cohorts, genomes/recruitment traits, transport/disturbance schedules, history/logs, cumulative conservation accounting, occupancy maps и P2.7 diagnostics.

P2.8 остаётся research-only proof. Он не заявляет production persistence ownership, canonical Time/Spatial ownership, network authority или species taxonomy.

## EVO1 lifecycle

```text
P2.1 .. P2.7 = ACCEPTED
P2.8          = ACCEPTED
ECO.EVO1      = COMPLETE
```

EVO1 semantics теперь frozen как базовый deterministic evolutionary-ecology research layer. Следующее развитие должно добавляться новыми checkpoint'ами без ретроактивного изменения accepted EVO1 evidence.

## Next

Следующий узкий checkpoint: `P3.1 Resource Competition`.

Он должен добавить детерминированную конкуренцию за ограниченные `light`, `water` и `nutrients`, conservation invariants, order/permutation independence и limiting-resource response. Это новый post-EVO1 research checkpoint; он не открывает production ownership и не меняет accepted EVO1 semantics.
