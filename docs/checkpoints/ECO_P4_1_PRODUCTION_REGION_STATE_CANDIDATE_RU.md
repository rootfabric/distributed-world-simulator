# ECO P4.1 — Production Ecology Region State — CANDIDATE

Статус: `IMPLEMENTED CANDIDATE / EXACT ATTACHED GODOT CONTRACT PASS / FULL REPOSITORY GATE PENDING`.

## Цель

P4.1 вводит production-facing границу между завершённым deterministic P3 research stack и будущим world/region runtime. Он отвечает только на вопрос: **как канонический ecology state принадлежит одному production region и как проверить его identity**, не выбирая scheduler, storage или network ownership.

## Контракт

`EcologyRegionState` содержит `region_id`, `ecology_generation`, `last_simulated_world_time`, immutable pin accepted P3.8 aggregate, deep-copied validated P3.8 semantic state, его `state_hash` и independent P4.1 `region_state_hash`.

`region_state_hash` хеширует fixed-order scalar vector и связывает вложенную экологию через validated P3.8 `state_hash`. Nested dictionary не становится вторым P3 canonicalizer. Create/extract используют deep copy.

P4.1 не определяет ecology tick, catch-up, production save/database format, region owner/server handoff, replication или client presentation. P3.8 checkpoint codec остаётся research reference proof и не объявляется production save format.

## Evidence

Exact attached Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Новый contract прошёл strict API-compatible P3.8 harness в трёх fresh processes: `PASS (47 assertions) x3`, logs byte-identical, `log_sha256=dd0956c3d2618358ec5987f1b9b2ddb6a411f8e9f55d3e2336379f0e17ff4315`.

На exact hashing semantics воспроизведены hash vectors из frozen accepted P3.8 semantic hashes:

```text
region_zero_hash=2d7fc8f595dbe5e55e29a0dca1256a9f4ccebe4176ec8d53c9bf66671ac3b7b4
region_cut_hash=fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c
other_region_hash=d4f0cd4890678747ef2f2399bcfd500282a3840af43ea37913ee78c39b17c3e5
expected_full_repo_aggregate=1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717
```

Committed acceptance test использует реальный P3.1→P3.8 fixture и frozen P3.8 initial/generation-5 identities. Полный repository runtime gate в текущей sandbox не исполнен, поэтому P4.1 не повышен до ACCEPTED.

## Следующий gate

Запустить `RUN_ECO_P4_1_TESTS.ps1` в полном checkout на exact Godot. Только после exact aggregate PASS можно принять P4.1 и открыть P4.2 Deterministic Ecology Clock.
