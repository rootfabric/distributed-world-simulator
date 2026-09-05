# FABRIC B0.6-D — Persistence / Restart: EXACT PASS

## Exact subject и runtime

Branch: `research/fabric-bake0-6-adaptive-physical-fidelity-r1`.
Runtime HEAD: `2254b450b4d31832a6c143fc85096372679c6bc6`.
Runtime TREE: `82532abb755b6b652b84a96ff5d92a8225cd8dba`.
Godot: `4.7.1.stable.double.custom_build.a13da4feb`.
Binary SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Два завершённых запуска из разных новых Git checkout: `exact-a` и `exact-b`.
В обоих fresh import: exit 0, fatal 0; runtime runner: exit 0. Это измеренные
результаты, не перенос прежних PASS и не GitHub Actions, остающийся в очереди.
Machine evidence: `validation/fabric_b0_6/exact-replay.v1.json`.
Raw archive: `DWS_B0_6_EXACT_RUNTIME_EVIDENCE.zip`, SHA-256 `f0fe97043abd8b1bc774a9e6c471b46c6f74b72d999bd836f1368b6fd3f2faaf`.

## Реализация и acceptance

Implementation: `scripts/research/fabric_bake0/adaptive_physical_fidelity_recovery_v1.gd`.
Runner: `RUN_FABRIC_B0_6_D_TESTS.sh`.
Assertions на каждый replay: **69 + 10 + 5 = 84**.
Результат обоих запусков: **PASS**, exit **0**.

Cold/warm restart, source/dependency mismatch, corruption, unsafe restored mode, pending demotion/promotion, causal DORMANT wake, crash before committed transition, повторное recovery. Capsule NONCANONICAL/DERIVED/DISCARDABLE; authoritative source revision не создаётся из кэша. Дополнительно реальная запись на диск и чтение в отдельном процессе Godot; JSON integer normalization проверена.

## Fresh-process equality

Оба запуска дали одинаковые значения:

```text
B06D_RECOVERY_HASH=f9613fe30c97322cfd1f81d6f74608a0bc58e51f6dbb8be6af37dff177ba8bba
B06D_DISK_RECOVERY_HASH=ab2287a06a5427e5d73f15b5c7a6ad11267f5f3c9aad1e519a4cdc5cc13fc1f9
```

69 основных assertions + 10 writer + 5 reader. Disk restart не эмулируется одним процессом.
