# V0 / SM0 P4 — TARGET-RESTART HARDENING CANDIDATE

Дата: 2026-08-16

Статус:

```text
IMPLEMENTED CANDIDATE
PROJECT CONTROL PASS
WINDOWS FAULT VERIFICATION REQUIRED
INDEPENDENT CRITICAL REVIEW REQUIRED
P4 NOT ACCEPTED
P5 BLOCKED
```

## 1. Exact boundary

PR:

```text
#102
SM0: two-authority seamless handoff lab
```

Branch:

```text
feature/sm0-two-authority-seamless-handoff-lab
```

Последний ранее подтверждённый Windows P4 WAN runtime HEAD:

```text
5f3f967f9be779a79d45be5b18ac78ad954f7dd4
```

На нём подтверждены:

- P4 short 4/4 fast;
- P4 stress 20/20 fast;
- legacy stress 20/20 legacy;
- controlled WAN 10/20/30/45 ms one-way;
- 40/40 measured handoffs были P4 FAST;
- identity_changes = 0;
- objective WAN PASS.

Текущий P4 restart-hardening **code/test evidence HEAD**:

```text
a6f76e4cfbb48099b3dbe781bc771f3b1bec4a03
```

Project Control на этом code/test HEAD:

```text
run #739
SUCCESS
```

Последующий commit этого checkpoint является documentation-only и не должен подменять runtime implementation boundary.

Project Control не является Godot runtime acceptance.

## 2. Почему потребовался repair

После WAN PASS оставался известный CRITICAL availability gap:

```text
target PREWARMED ACK
-> target process restart
-> target loses transient reservation
-> source crosses and retires canonical writer
-> FAST_COMMIT reaches restarted target
-> target rejects SM0_P4_FAST_COMMIT_WITHOUT_PREWARM
```

Старое поведение было fail-closed и не создавало split brain, но handoff терял progress после того, как source writer уже был retired.

Критический разбор также потребовал усилить:

- aggregate A+B writer evidence;
- generic CLIENT_JOIN admission после restart/HELLO;
- exact replay identity FAST_COMMIT/COMMITTED;
- client REDIRECT replay identity;
- single reservation per player/source-target epoch;
- restart/reconnect escape paths;
- recovery semantics при disconnected, но уже существующей canonical truth;
- durability ordering между in-memory target import и durable `TARGET_COMMITTED`.

## 3. Реализованный bounded hardening

Repair намеренно переиспользует существующий SM0 recovery foundation вместо создания второй независимой recovery architecture.

### 3.1 Durable target PREWARM reservation

Успешная target reservation записывается до success PREWARM ACK.

Runtime использует тот же recovery root, что и существующий SM0 recovery layer.

### 3.2 Durable PREWARM proof beyond live TTL

Live PREWARM TTL остаётся bounded и определяет, может ли source начать новый fast crossing.

После того как target уже durably подтвердил reservation, отдельно сохраняется immutable proof:

```text
prewarm id
prewarm checksum
player identity
source/target authority
source/target epoch
source directory revision
```

Proof не содержит mutable player state и сам по себе не создаёт writer.

После target restart, если live reservation уже истекла, FAST_COMMIT может rehydrate короткую локальную reservation только при совпадении всех fences:

- exact durable prewarm proof;
- prewarm checksum;
- valid final handoff package;
- valid committed directory;
- package/prewarm route + identity + epoch match;
- target directory state compatible;
- target ещё не содержит canonical player truth.

FAST_COMMIT без ранее durably ACKed proof не может создать reservation.

### 3.3 Recovered disconnected player truth — hard fence

Во время canonical recovery transport session намеренно очищается, поэтому восстановленный player record может быть:

```text
connected = false
transport_session_id = ""
```

Это всё равно canonical gameplay truth.

Предыдущий вариант proof guard проверял только `connected=true`, что оставляло stale-proof escape после durable target recovery.

На code/test HEAD `a6f76e4...` guard усилен:

```text
любое существование canonical player record
=> old durable PREWARM proof не может импортировать player заново
```

Исключение не требуется для intended target-restart path: snapshot `PREWARM_RESERVED` не содержит target player truth до финального FAST_COMMIT.

### 3.4 Proof cleanup только после durable TARGET_COMMITTED

Ещё один найденный durability race:

```text
FAST_COMMIT validates
-> target player imported in memory
-> _committed_transfers populated
-> canonical TARGET_COMMITTED disk persistence fails
-> ACK не уходит
```

Ранее closure мог после возврата из parent call увидеть in-memory `_committed_transfers` и удалить durable PREWARM proof, хотя canonical commit ещё не был durable.

Это исправлено.

Proof теперь можно consume только если inherited recovery ledger подтверждает:

```text
_recovery_persisted_commits.has(transfer_id)
```

При отсутствии canonical durability proof сохраняется и emitting marker:

```text
SM0_P4_PREWARM_PROOF_RETAINED_UNTIL_TARGET_DURABLE
```

Следующий exact FAST_COMMIT retry может завершить canonical persistence без второго player import; только после этого proof cleanup разрешён.

### 3.5 Source-retire recovery

P4 fast source state связывается с существующим canonical `SOURCE_RETIRED` recovery snapshot.

После source restart уже retired writer не должен автоматически воскресать.

После полностью завершённого fast handoff side-journal пишет completed tombstone; более поздний restart source не должен resurrect старый pending transfer.

### 3.6 Peer incarnation

HELLO/HELLO_ACK в P4 несут process incarnation id.

Если target перезапустился до source retirement и source увидел новую incarnation, старый ACKed prewarm инвалидируется и source может безопасно уйти в legacy fallback до crossing.

После source retirement writer не resurrect; recovery идёт через durable target proof.

### 3.7 JOIN admission

P4 generic CLIENT_JOIN запрещён:

- до peer synchronization;
- на post-bootstrap owner, если canonical truth должна появиться только через committed activation.

Единственное bootstrap исключение:

```text
authority A
owner A
authority_epoch = 1
directory revision = 1
```

### 3.8 Replay identity

FAST_COMMIT / COMMITTED binding включает:

```text
package_checksum
prewarm_id
prewarm_checksum
directory_checksum
```

Exact duplicate разрешён как replay.

Тот же transfer id с другим binding fail-closed как conflict.

Client completed REDIRECT replay также связан с route / target / epoch / player identity / directory fingerprint.

### 3.9 Global writer evidence

Отдельный aggregate A+B writer analyzer проверяет:

```text
writer_count(A) + writer_count(B) <= 1
```

Есть негативный self-test, который обязан поймать synthetic A=1 + B=1 overlap.

## 4. Durable-proof focused regression

Добавлены:

```text
tests/runtime/seamless/sm0/sm0_p4_durable_proof_test_server.gd
tests/runtime/seamless/sm0/test_sm0_p4_durable_proof_recovery.gd
RUN_V0_SM0_P4_DURABLE_PROOF_RECOVERY.ps1
```

Regression на `a6f76e4...` обязан доказать:

1. durable proof переживает потерю process-local live reservation;
2. proof остаётся usable после времени > одного live TTL;
3. существующая canonical target truth блокирует proof import даже если transport disconnected;
4. changed prewarm checksum блокируется;
5. directory drift блокируется;
6. exact FAST_COMMIT rehydrates reservation;
7. simulated in-memory target commit **без** canonical durability не удаляет proof;
8. exact retry завершает durability без второго import;
9. proof consumes только после durable `TARGET_COMMITTED`;
10. exact post-durability replay ACKed;
11. conflicting replay rejected.

Этот тест пока не считается Windows PASS до выполнения exact-head Godot run.

## 5. Physical target-restart-after-TTL gate

Основной fault runner:

```text
RUN_V0_SM0_P4_TARGET_RESTART_FAULT.ps1
```

Runner исключает старый shortcut через ещё живую reservation.

Default:

```text
live PREWARM TTL = 3000 ms
PostCrashHoldMs = 4000 ms
```

Минимально разрешённый `PostCrashHoldMs` — 3500 ms.

Обязательный physical ordering:

```text
PREWARM ACK durable
-> target B exits with code 86
-> source A crosses
-> SOURCE_RETIRED
-> B remains physically down > live PREWARM TTL
-> target B restarts from same recovery root
-> SM0_P4_PREWARM_PROOFS_RESTORED
-> SM0_P4_PREWARM_REHYDRATED_FROM_DURABLE_PROOF
-> SM0_P4_FAST_COMMIT_ACCEPTED
-> client activates
```

PASS невозможен только на основании восстановления live reservation: runner требует оба proof-specific marker.

Fault evidence schema:

```text
distributed_world_simulator.sm0_p4_closure_fault_evidence.v2
```

и записывает:

```text
live_prewarm_ttl_ms
post_crash_hold_ms
target_live_reservation_restored = false
target_durable_proof_restored = true
target_reservation_rehydrated_from_proof = true
```

Также runner перезапускает retired source A после completed handoff и немедленно делает fresh CLIENT_JOIN probe.

Restarted stale A не должен принять JOIN или стать writer.

Runner дополнительно выполняет:

- focused P4 hardening test;
- focused durable-proof test;
- aggregate writer analyzer negative self-test;
- final base SM0 analyzer;
- final aggregate A+B writer analyzer.

## 6. Что ещё не доказано

Runtime PASS с `5f3f967...` нельзя переносить на `a6f76e4...`: authority/recovery protocol изменился.

Обязательны fresh exact-head Windows runs.

Рекомендуемый порядок:

```powershell
git fetch origin
git merge --ff-only origin/feature/sm0-two-authority-seamless-handoff-lab
git rev-parse HEAD
git status --short

.\RUN_V0_SM0_P4_DURABLE_PROOF_RECOVERY.ps1
.\RUN_V0_SM0_P4_TARGET_RESTART_FAULT.ps1 -Restart
.\RUN_V0_SM0_P4_ACCEPTANCE.ps1 -Handoffs 4 -Restart
.\RUN_V0_SM0_P4_ACCEPTANCE.ps1 -Final -Restart
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Final -Restart
.\RUN_V0_SM0_P4_CONTROLLED_NETWORK_LATENCY_MATRIX.ps1 -Restart -RequireHandoffs 10
```

После `git rev-parse HEAD` SHA должен совпадать с актуальным remote branch HEAD. Если branch HEAD отличается от `a6f76e4...` только documentation-only commit этого checkpoint, runtime implementation boundary остаётся `a6f76e4...`; в evidence необходимо записать и checked-out HEAD, и implementation HEAD.

## 7. Почему WAN matrix нужно повторить

Нельзя переиспользовать performance acceptance `5f3f967...` как acceptance нового protocol candidate.

Hardening добавляет durable writes до protocol ACK/commit boundaries, поэтому необходимо проверить:

- fast path всё ещё используется 40/40;
- legacy fallback не просочился в measured handoffs;
- p50/p95 не получили неприемлемый regression;
- aggregate writer invariant остаётся <= 1;
- identity/epoch остаются стабильными.

## 8. Отдельный будущий fault vector

Обнаружено ещё одно окно:

```text
source runtime leave / directory advance
-> source crash
-> durable SOURCE_RETIRED snapshot ещё не завершён
```

Это не текущий target-restart blocker и не должно раздувать P4 бесконечно.

Оно должно быть занесено в будущую P11 simultaneous faults / crash-window matrix.

До появления target writer это окно не создаёт двух одновременно активных writer, но может потерять progress/state и поэтому должно получить отдельную fault semantics позже.

## 9. Acceptance boundary

P4 можно закрыть только после:

```text
focused hardening regression PASS
focused durable-proof-after-TTL + target-durability regression PASS
physical target-restart-after-TTL recovery PASS
restart/reconnect admission PASS
aggregate A+B writer PASS
P4 short PASS
P4 stress PASS
legacy stress PASS
controlled WAN matrix PASS on repaired exact HEAD
independent CRITICAL review PASS
```

До этого:

```text
P4 ACCEPTED = NO
P5 START = NO
```

После полного P4 closure следующий bounded runtime пункт roadmap:

```text
P5 — two players / two authorities / read-only cross-authority projections
```

P5 не должен менять canonical writer rules, а должен вводить только projection/interest layer поверх уже доказанного handoff protocol.
