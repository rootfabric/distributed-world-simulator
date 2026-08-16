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

Текущий hardening candidate HEAD на момент создания checkpoint:

```text
53c7a5bb665fd1697c9ee5d277fa9b130e38451e
```

Project Control:

```text
run #730
SUCCESS
```

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

Независимый критический разбор также потребовал усилить:

- aggregate A+B writer evidence;
- generic CLIENT_JOIN admission после restart/HELLO;
- exact replay identity FAST_COMMIT/COMMITTED;
- client REDIRECT replay identity;
- single reservation per player/source-target epoch;
- restart/reconnect escape paths.

## 3. Реализованный bounded hardening

Repair намеренно переиспользует существующий SM0 recovery foundation вместо создания второй независимой recovery architecture.

### 3.1 Durable target PREWARM reservation

Успешная target reservation должна быть записана до success PREWARM ACK.

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
- target ещё не содержит активную canonical player truth.

FAST_COMMIT без ранее durably ACKed proof не может создать reservation.

### 3.3 Source-retire recovery

P4 fast source state связывается с существующим canonical `SOURCE_RETIRED` recovery snapshot.

После source restart уже retired writer не должен автоматически воскресать.

После полностью завершённого fast handoff side-journal пишет completed tombstone; более поздний restart source не должен resurrect старый pending transfer.

### 3.4 Peer incarnation

HELLO/HELLO_ACK в P4 несут process incarnation id.

Если target перезапустился до source retirement и source увидел новую incarnation, старый ACKed prewarm инвалидируется и source может безопасно уйти в legacy fallback до crossing.

После source retirement writer не resurrect; recovery идёт через durable target proof.

### 3.5 JOIN admission

P4 generic CLIENT_JOIN запрещён:

- до peer synchronization;
- на post-bootstrap owner, если canonical truth должна появиться только через committed activation.

Единственное bootstrap исключение остаётся:

```text
authority A
owner A
authority_epoch = 1
directory revision = 1
```

### 3.6 Replay identity

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

### 3.7 Global writer evidence

Добавлен отдельный aggregate A+B writer analyzer.

Он проверяет не только каждый server локально, но и максимум:

```text
writer_count(A) + writer_count(B) <= 1
```

Есть негативный self-test анализатора, который обязан поймать synthetic A=1 + B=1 overlap.

## 4. Новый durable-proof regression

После hardening review обнаружен дополнительный evidence gap:

старый physical target-restart harness перезапускал B достаточно быстро, чтобы восстановить ещё живую 3-second reservation. Это не доказывало новую семантику proof после истечения live TTL.

Добавлены:

```text
tests/runtime/seamless/sm0/sm0_p4_durable_proof_test_server.gd
tests/runtime/seamless/sm0/test_sm0_p4_durable_proof_recovery.gd
RUN_V0_SM0_P4_DURABLE_PROOF_RECOVERY.ps1
```

Focused regression обязан доказать:

1. durable proof переживает потерю process-local live reservation;
2. proof остаётся usable после времени > одного live TTL;
3. active target canonical truth блокирует proof import;
4. changed prewarm checksum блокируется;
5. directory drift блокируется;
6. exact FAST_COMMIT rehydrates reservation и commits один раз;
7. успешный commit consumes proof;
8. exact post-recovery replay ACKed;
9. conflicting replay rejected.

Этот тест пока не считается PASS до выполнения exact-head Windows Godot run.

## 5. Physical target-restart harness

Основной fault runner:

```text
RUN_V0_SM0_P4_TARGET_RESTART_FAULT.ps1
```

Должен физически доказать ordering:

```text
PREWARM ACK durable
-> target B exits
-> B remains down
-> source A crosses
-> SOURCE_RETIRED
-> target B restarts from same recovery root
-> FAST_COMMIT accepted
-> client activates
```

Также runner перезапускает retired source A после completed handoff и немедленно делает fresh CLIENT_JOIN probe.

Restarted stale A не должен принять JOIN или стать writer.

## 6. Что ещё не доказано

На current hardening candidate пока нельзя переносить runtime PASS с `5f3f967...`, потому что authority/recovery protocol изменился.

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

После `git rev-parse HEAD` SHA должен совпадать с актуальным remote HEAD, который будет указан в PR после всех documentation-only commits.

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
focused durable-proof-after-TTL regression PASS
physical target-restart recovery PASS
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
