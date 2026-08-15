# SM0 H4.3 — work log

Статус: **FIX1 IMPLEMENTED / WINDOWS RUNTIME DEFAULT RE-RUN PENDING**.

Scope: branch-local experimental `feature/sm0-two-authority-seamless-handoff-lab`.

Никакой global / production / V0-S1 acceptance этим документом не объявляется. `SERVER_HANDOFF` остаётся CRITICAL-risk и вне разрешённого V0-S1 runtime frontier.

## Source of truth

H4.3 начат от H4.2 evidence HEAD:

`ed5d7d3d26c4ff33d707087fea91d33aba6f449f`

H4.2 tested runtime SHA:

`3e95dd881e55784bfe15a9901e7d1fe9bac143f9`

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

Исправление: fresh Stage PREPARED подавляет одновременно:

- `PLAYER_HANDOFF_COMMIT`;
- `HANDOFF_REDIRECT`.

Exact recovery-setup replay старого transfer пропускает оба сообщения.

### 6. Acceptance runner

Commit:

`0cdf1c937bee3df4a0a5cbaa61b31043eea04761`

File:

`RUN_V0_SM0_RECOVERY_OF_RECOVERY_ACCEPTANCE.ps1`

Runner проверяет fail-closed:

- один transfer id через все три outage одной chain;
- один client PID;
- PREPARED durable pair;
- COMMITTED durable pair;
- ACTIVE_OWNER durable pair;
- строгий рост target recovery generation;
- source остаётся exact `SOURCE_RETIRED` non-writer;
- canonical target import ровно один после PREPARED recovery;
- отсутствие duplicate canonical import после COMMITTED/ACTIVE recovery;
- отсутствие `SM0_COMMIT_WITHOUT_PREPARE`;
- отсутствие invariant violation;
- exactly-one crossing после terminal ACTIVE_OWNER restore;
- contiguous directory epoch;
- identity changes = 0;
- zero-authority interval при каждом outage.

DEFAULT:

- 1 chain;
- 1 handoff A -> B;
- 3 total outages;
- expected final directory epoch 2.

FINAL:

- 2 chains в одной client session;
- A -> B, затем B -> A;
- 6 total outages;
- expected final directory epoch 3.

PowerShell runner сразу использует constructor-created generic Lists и `.ToArray()` для summary, чтобы не повторять H4.1 generic-list binder defect. Stage assertions синхронизируются по exact H4.3 crash/suppression markers перед чтением durable evidence.

### 7. First Windows runtime finding — PREPARED fault ordering

Первый DEFAULT запуск выполнен на exact candidate:

`af5541f2d983cf9870a213c1644810fa416780e7`

Exact Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

До live H4.3 campaign прошли:

- compile-smoke 9 scripts;
- handoff import 22 assertions;
- healthy SM0 acceptance 2/2;
- contracts 15 assertions;
- H4.3 compile checks;
- TARGET_PREPARED recovery regression 32 assertions;
- ACTIVE_OWNER recovery regression 41 assertions;
- SOURCE_RETIRED recovery regression 37 assertions.

Live campaign запустил A, B и один client, после чего runner ожидал первый `SM0_H43_CRASH_POINT(PREPARED)` и не получал его.

Root cause установлен в test-only H4.3 fault orchestration: override `_send_source_commit()` проверял `_recovery_last_phase == SOURCE_RETIRED` до вызова parent recovery method, хотя именно parent `_send_source_commit()` выполняет canonical `_ensure_source_retire_persisted()` перед отправкой COMMIT. В результате первый fresh вызов видел ещё пустую durable phase, уходил в `super._send_source_commit()`, и COMMIT мог выйти в сеть вместо PREPARED fault.

Repair commit:

`9ffa0d9eb19d354bbf8d6b68bba7e9346188418d`

Исправление не меняет production recovery algorithm. H4.3 fault node теперь для fresh source сначала явно вызывает существующий canonical `_ensure_source_retire_persisted(transfer_id)`, проверяет успех write-before-fault, и только после этого suppress-ит COMMIT и создаёт PREPARED crash point. Exact recovery-setup replay старого T по-прежнему bypass-ит fault и проходит через parent replay path.

Новый invariant test-only слоя при failure durability:

`SM0_H43_SOURCE_RETIRE_PERSIST_FAILED`.

## Static workflow

Project Control run #600 для commit `0cdf1c937bee3df4a0a5cbaa61b31043eea04761`:

**SUCCESS**.

Project Control run #601 для progress HEAD `af5541f2d983cf9870a213c1644810fa416780e7`:

**SUCCESS**.

Это static/control evidence. Godot runtime acceptance ещё не объявлена.

## Следующий gate

Повторить DEFAULT на Windows exact custom Godot после runtime-discovered FIX1 и потребовать:

```text
SM0-H4.3 recovery-of-recovery same-transfer campaign: PASS
chains 1/1
outages 3/3
handoffs 1/1
final directory epoch 2
identity changes 0
```

После DEFAULT PASS — без изменения runtime candidate выполнить FINAL 2 chains / 6 outages. После FINAL PASS записать отдельный H4.3 runtime evidence document.

Следующий визуальный checkpoint после H4.3: P2 Graphical Recovery Lab.
