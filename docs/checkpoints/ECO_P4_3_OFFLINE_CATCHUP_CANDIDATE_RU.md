# ECO P4.3 — Offline Catch-up — CANDIDATE

Статус: `CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_FULL_CHAIN_GATE_PENDING`.

Parent P4.2: `607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e` — ACCEPTED.

P4.3 добавляет production-facing deterministic catch-up state поверх accepted P4.2 clock. Источник времени остаётся внешним: слой принимает явный `observed_target_world_time` или elapsed interval и **не читает wall clock / OS time**.

## Зафиксированный контракт

- backlog вычисляется только через P4.2 `due_plan`;
- один `advance_batch` ограничен `P3.8 MAX_ADVANCE_STEPS`;
- backlog больше одного P3.8 вызова хранится явно и обрабатывается порциями;
- дробный остаток offline time сохраняется в observed horizon и не теряется после обработки целых ecology generations;
- одинаковый start + clock + horizon дают одинаковый canonical RegionState независимо от допустимого разбиения на batches;
- horizon может только расти; rewind fail-closed;
- P4.3 не владеет persistence/storage, handoff, replication или client authority.

## Targeted exact-Godot evidence

Exact Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

`PASS (34 assertions) x3`; fresh-process logs byte-identical; log SHA-256:
`ed5b69dade7accabef494ca5ed8aa80ef8f29e2bc8482e2d3a540514d7e0771e`.

Targeted hashes:

`aggregate=30e34db2b5d9a0f87b3b43420058cf63baa6b6b531c6ea232b9ffb6176929e02`
`catchup=e399db6ae5d8f3715ca6592e739b63780263b23b646edb7bc8002fbf7e85a146`
`region=6fcd95f10c5ebd2094ff41beb30912bb7c7fea5afd59c7d59d715d81ecaf11e0`.

Targeted harness использует deterministic P3 persistence stub только для проверки P4.1/P4.2/P4.3 interface semantics. Это **не** acceptance evidence полного P3.1→P4.3 пути.

## Full-chain gate

Committed runner должен прогнать accepted P4.2 parent regression и P4.3 fresh A/B на реальном P3 chain. Ожидаемые frozen identities:

`aggregate=4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62`
`catchup=cc2a4815e1eae75b879ea52d8ba404880c69344928f953e8aaa38bd062b1ce3a`
`generation_5_region=fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c`.

P4.4 Production Persistence остаётся CLOSED до отдельного P4.3 lifecycle acceptance.
