# SM0 H4.3 — work log

Статус: **WINDOWS RUNTIME DEFAULT + FINAL PASS / EVIDENCE RECORDED**.

Scope: branch-local experimental `feature/sm0-two-authority-seamless-handoff-lab`.

Никакой global / production / V0-S1 acceptance этим документом не объявляется. `SERVER_HANDOFF` остаётся CRITICAL-risk и вне разрешённого V0-S1 runtime frontier.

## Source of truth

H4.3 начат от H4.2 evidence HEAD:

`ed5d7d3d26c4ff33d707087fea91d33aba6f449f`

H4.2 tested runtime SHA:

`3e95dd881e55784bfe15a9901e7d1fe9bac143f9`

Exact H4.3 DEFAULT + FINAL tested candidate:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

Exact Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Runtime evidence:

`docs/control/SM0_H4_3_RECOVERY_OF_RECOVERY_RUNTIME_EVIDENCE_RU.md`

## Динамика реализации

### 1. Design

Commit:

`b077b7bba5789a737d3bb3c1667f0e2caf6beee7`

File:

`docs/control/SM0_H4_3_RECOVERY_OF_RECOVERY_SAME_TRANSFER_DESIGN_RU.md`

Определена recovery-chain одного exact transfer:

`TARGET_PREPARED -> TARGET_COMMITTED -> ACTIVE_OWNER -> exactly-one completion`

между фазами выполняются три simultaneous dual-authority outage.

### 2. Initial H4.3 fault node

Commit:

`c5c7f24000606aa8c1c633bc20dd11b66cb1aad5`

File:

`scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_chain_fault.gd`

Добавлен отдельный test-only profile:

`h4-recovery-of-recovery-same-transfer-v1`

Production recovery algorithm не изменялся.

### 3. Exact setup replay discrimination

Commit:

`719176eabe2ddf1ac754a19f03ed1601184a1849`

До runtime review обнаружено, что process, восстановленный из предыдущей chain, позже может стать source нового transfer. Поэтому нельзя использовать общий `_recovery_restored` как признак replay.

Исправление: bypass разрешён только exact `SOURCE_RETIRED` transfer во время recovery setup. После setup новый transfer в том же процессе снова проходит Stage PREPARED fault.

### 4. Server routing

Commit:

`802f88b01f918e8d07043a15a557ef4df15fe4b5`

H4.3 profile направлен через отдельный `RecoveryChainFaultServerNode`.

H3.3/H3.4/H3.5/H4.1/H4.2 routing не изменён.

### 5. PREPARED redirect hold

Commit:

`6b7095ea466f4f32536a94cd7f1e707557ce7d0f`

До Windows runtime review обнаружено, что base `_commit_source_transfer()` после COMMIT сразу вызывает `HANDOFF_REDIRECT`.

Если подавлять только COMMIT, client может уйти на target до canonical target commit, и PREPARED boundary перестаёт быть чистым.

Исправление: fresh Stage PREPARED подавляет одновременно `PLAYER_HANDOFF_COMMIT` и `HANDOFF_REDIRECT`. Exact recovery-setup replay старого transfer пропускает оба сообщения.

### 6. Acceptance runner

Commit:

`0cdf1c937bee3df4a0a5cbaa61b31043eea04761`

File:

`RUN_V0_SM0_RECOVERY_OF_RECOVERY_ACCEPTANCE.ps1`

Runner fail-closed проверяет один transfer id через все три outage одной chain, один client PID, durable PREPARED/COMMITTED/ACTIVE_OWNER pairs, строгий рост target recovery generation, exact SOURCE_RETIRED non-writer source state, ровно один canonical target import, отсутствие duplicate canonical import, отсутствие `SM0_COMMIT_WITHOUT_PREPARE`, отсутствие invariant violation, exactly-one crossing после terminal restore, contiguous directory epoch, identity changes = 0 и zero-authority interval при каждом outage.

DEFAULT: 1 chain, A -> B, 3 outages, expected final directory epoch 2.

FINAL: 2 chains в одной client session, A -> B затем B -> A, 6 outages, expected final directory epoch 3.

### 7. First Windows runtime finding — PREPARED fault ordering

Первый DEFAULT запуск на candidate `af5541f2d983cf9870a213c1644810fa416780e7` дошёл до live H4.3 campaign, после чего не получил первый `SM0_H43_CRASH_POINT(PREPARED)`.

Root cause установлен в test-only H4.3 fault orchestration: override `_send_source_commit()` проверял `_recovery_last_phase == SOURCE_RETIRED` до вызова parent recovery method, хотя именно parent path выполняет canonical `_ensure_source_retire_persisted()` перед отправкой COMMIT. Первый fresh вызов видел ещё пустую durable phase и мог пропустить COMMIT вместо PREPARED fault.

Repair commit:

`9ffa0d9eb19d354bbf8d6b68bba7e9346188418d`

H4.3 fault node теперь для fresh source сначала вызывает существующий canonical `_ensure_source_retire_persisted(transfer_id)`, fail-closed проверяет durability, затем suppress-ит COMMIT и создаёт PREPARED crash point. Production recovery algorithm не изменён. Exact recovery-setup replay старого T по-прежнему bypass-ит fault.

Test-only invariant при failure durability:

`SM0_H43_SOURCE_RETIRE_PERSIST_FAILED`.

### 8. Windows DEFAULT runtime PASS after FIX1

Дата локального runtime: 2026-08-16.

Exact tested HEAD:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

One unchanged client PID `26228` пережил exact transfer `handoff/sm0/a/2/1` через:

- target B `TARGET_PREPARED generation=1`, source A `SOURCE_RETIRED generation=12`, kill gap `0 ms`;
- target B `TARGET_COMMITTED generation=2`, тот же source durable generation `12`, kill gap `0 ms`;
- target B `ACTIVE_OWNER generation=3`, тот же source durable generation `12`, kill gap `0 ms`;
- terminal restore и crossing #1 ровно один раз.

Analyzer: PASS, handoffs `1/1`, events `118`, final directory epoch `2`, identity changes `0`.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH43\logs\20260816-025910`

### 9. Windows FINAL runtime PASS

Дата локального runtime: 2026-08-16.

Exact tested HEAD остался тем же:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

Same client PID:

`27184`

Chain 1 A -> B использовала один exact transfer `handoff/sm0/a/2/1` через target generations `PREPARED=1`, `COMMITTED=2`, `ACTIVE=3`, source A оставался `SOURCE_RETIRED generation=12`; все три kill gap `0 ms`; crossing #1 завершён ровно один раз.

Chain 2 B -> A использовала один exact transfer `handoff/sm0/b/3/1` через target generations `PREPARED=13`, `COMMITTED=14`, `ACTIVE=15`, source B оставался `SOURCE_RETIRED generation=6`; все три kill gap `0 ms`; crossing #2 завершён ровно один раз.

FINAL facts:

- chains `2/2`;
- outages `6/6`;
- 12 induced authority process deaths;
- handoffs `2/2`;
- analyzer PASS, events `199`;
- final directory epoch `3`;
- identity changes `0`;
- один client process пережил весь campaign.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH43\logs\20260816-030158`

H4.3 summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH43\logs\20260816-030158\h43-summary.json`

## Static workflow

Project Control run #600 для commit `0cdf1c937bee3df4a0a5cbaa61b31043eea04761`: **SUCCESS**.

Project Control run #601 для progress HEAD `af5541f2d983cf9870a213c1644810fa416780e7`: **SUCCESS**.

Project Control run #604 для exact runtime candidate `1126ec53ddf036389d2d11aa5211147b5cd7e320`: **SUCCESS**.

## H4.3 verdict

H4.3 закрыт как **branch-local experimental runtime evidence** на exact tested SHA `1126ec53ddf036389d2d11aa5211147b5cd7e320`.

Evidence commit после runtime находится поверх tested candidate только в docs history; он не меняет смысл exact tested runtime SHA.

Следующий visual checkpoint: **P2 Graphical Recovery Lab** — визуализация authority ownership, durable recovery phase, process outage/restart и same-transfer recovery без объявления production/global acceptance.
