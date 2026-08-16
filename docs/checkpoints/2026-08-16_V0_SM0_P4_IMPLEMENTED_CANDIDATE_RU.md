# V0-SM0 P4 — Prewarmed Fast Handoff implemented candidate

**Дата:** 2026-08-16  
**Статус:** `IMPLEMENTED CANDIDATE / WINDOWS VERIFICATION REQUIRED / NOT ACCEPTED`  
**Ветка:** `feature/sm0-two-authority-seamless-handoff-lab`  
**PR:** `#102 — SM0: two-authority seamless handoff lab`  
**Implementation runtime/evidence HEAD:** `ce18f3f62db6b2c9970dce86c78803bb142d239c`  
**Authorized work order:** `docs/checkpoints/2026-08-16_V0_SM0_P4_WORK_ORDER_RU.md`  
**Risk:** `CRITICAL — cross-server authority transition`

> Этот checkpoint фиксирует наличие P4 candidate в ветке. Он не является acceptance, merge approval или разрешением переходить к P5.

## 1. Что реализовано

P4 добавлен поверх доказанного V2 SM0 handoff как **opt-in** режим:

```text
SM0_P4_FAST_HANDOFF=1
```

Обычные P3/P3.1 runner-ы без этой переменной продолжают использовать legacy:

```text
PREPARE -> PREPARED -> source retire -> COMMIT + REDIRECT
```

P4 путь:

```text
source still canonical writer
        |
        | near boundary
        v
PLAYER_HANDOFF_PREWARM
        |
        v
target metadata-only reservation
        |
PLAYER_HANDOFF_PREWARMED
        |
        | real crossing
        v
final canonical handoff package
        |
source freeze + source writer retire
        |
directory epoch/revision advance
        |
        +-----------------------------+
        |                             |
PLAYER_HANDOFF_FAST_COMMIT       HANDOFF_REDIRECT
        |                             |
target validates reservation          |
+ final package + directory            |
        |                             |
target canonical import/commit         |
        +-------------+---------------+
                      |
                CLIENT_ACTIVATE
```

## 2. Prewarm остаётся metadata-only

Добавлен контракт:

```text
distributed_world_simulator.sm0_player_handoff_prewarm.v1
```

Он содержит только:

```text
prewarm_id
logical_player_id
player_entity_id
source/target authority_id
source/target zone_id
source_authority_epoch
target_authority_epoch
source_directory_revision
ttl_ms
checksum
```

Контракт специально отклоняет presence mutable player fields:

```text
position
velocity
orientation_yaw
last_input_sequence
state_revision
ownership_epoch
session_id
```

Target prewarm не вызывает `authority.join()`, не импортирует player state и не меняет directory owner.

## 3. Исправление clock contract

Design brief первоначально обсуждал absolute `expires_at_msec`.

Это небезопасно между процессами: `Time.get_ticks_msec()` имеет process-local monotonic origin.

Runtime P4 использует:

```text
ttl_ms = 3000
```

Source и target независимо вычисляют собственный local expiry deadline. Межпроцессное сравнение monotonic timestamps отсутствует.

## 4. Fast commit fences

Перед target import проверяются:

```text
handoff package checksum/schema
final directory checksum/schema
transfer_id binding
prewarm_id + prewarm checksum
player identity
source/target authority route
source/target zone route
source epoch
exact target epoch = source + 1
source directory revision
final directory revision = source revision + 1
final directory owner = target
reservation local TTL
current target directory is either exact source state
  or exact already-observed final directory
```

Exact committed replay разрешён только для того же transfer/package/prewarm/directory identity. Конфликт отклоняется.

## 5. Single-writer ordering

P4 сохраняет порядок:

```text
source freeze
-> source authority.leave()
-> directory advance
-> FAST_COMMIT + REDIRECT
-> target authority.join()/import
-> target commit
-> client activation
```

Target `CLIENT_ACTIVATE` по-прежнему не ACK-ается, пока `_committed_transfers` не содержит transfer.

До crossing source остаётся единственным writer. Prewarm reservation не является writer и не содержит mutable canonical state.

## 6. Legacy fallback

Если в момент crossing source не имеет fresh ACKed reservation, P4 пишет:

```text
SM0_P4_FAST_FALLBACK
```

и вызывает существующий proven legacy `_begin_handoff()`.

Причины включают:

```text
NO_PREWARM
PREWARM_NOT_ACKED
PREWARM_EXPIRED
PLAYER_IDENTITY_MISMATCH
AUTHORITY_EPOCH_CHANGED
DIRECTORY_REVISION_CHANGED
```

Это сохраняет известный P3 путь вместо попытки fast transfer без source-side reservation proof.

## 7. Controlled latency ordering

Существующий `sm0_authority_server_node_network_delay.gd` сохраняет FIFO ordering отдельно для control и gameplay channel через monotonic `*_last_*_due_ms`.

Это важно для P4: crossing `MOVE_ACK` и следующий `HANDOFF_REDIRECT` находятся в одном gameplay channel, поэтому deterministic jitter shaper не переставляет redirect перед accepted crossing ACK.

P4 control messages автоматически проходят через существующий shaper, потому что `PLAYER_HANDOFF_*` использует тот же `_send_control()` path.

## 8. Evidence changes

`ANALYZE_V0_SM0_LOGS.ps1` теперь различает два допустимых path:

```text
LEGACY:
  SM0_HANDOFF_PREPARED

P4_FAST:
  SM0_P4_FAST_HANDOFF_BEGIN
  SM0_P4_PREWARM_RESERVED
  SM0_P4_PREWARMED
  SM0_P4_FAST_COMMIT_ACCEPTED
```

Общие hard phases сохраняются:

```text
SM0_SOURCE_FROZEN
SM0_DIRECTORY_COMMITTED
SM0_SOURCE_RETIRED
SM0_TARGET_AUTHORITY_COMMITTED
SM0_TARGET_ACTIVATED
```

`summary.json` дополнительно содержит:

```text
p4_fast_handoffs
legacy_handoffs
p4_fast_commit_events
```

## 9. Focused contract regression

`tests/runtime/seamless/sm0/test_sm0_contracts.gd` расширен проверками:

- valid metadata-only prewarm;
- no position/velocity/state/session leakage;
- checksum tamper rejection;
- bounded TTL rejection;
- mutable state injection rejection;
- authority epoch jump rejection.

Existing `RUN_V0_SM0_ACCEPTANCE_R2.ps1` уже compile-checks `sm0_contracts.gd` и `sm0_authority_server_node_v2.gd`, поэтому P4 acceptance runner переиспользует этот compile-smoke.

## 10. Отдельные runner-ы

### Local multi-process P4

```powershell
.\RUN_V0_SM0_P4_ACCEPTANCE.ps1 -Handoffs 4 -Restart
```

Stress:

```powershell
.\RUN_V0_SM0_P4_ACCEPTANCE.ps1 -Final -Restart
```

P4 wrapper считается PASS только когда:

```text
p4_fast_handoffs == expected handoffs
legacy_handoffs == 0
```

То есть незаметный fallback не может быть выдан за P4 success.

### Controlled WAN P4 matrix

```powershell
.\RUN_V0_SM0_P4_CONTROLLED_NETWORK_LATENCY_MATRIX.ps1 -Restart -RequireHandoffs 10
```

После обычной WAN-10/20/30/45 matrix wrapper сверяет каждый client-measured `transfer_id` с server event:

```text
SM0_P4_FAST_COMMIT_ACCEPTED
```

и создаёт:

```text
p4-fast-evidence-summary.json
```

Если хотя бы один измеренный handoff ушёл в legacy/fallback, P4 matrix завершается FAIL.

## 11. Legacy regression command

Legacy baseline остаётся отдельным и P4 не включается автоматически:

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Final -Restart
```

Это требуется прогнать после P4 exact-head runtime проверки, чтобы убедиться, что старый маршрут не сломан.

## 12. Control evidence на implementation HEAD

GitHub Project Control для exact implementation/evidence HEAD:

```text
ce18f3f62db6b2c9970dce86c78803bb142d239c
run #677
conclusion: SUCCESS
```

Job подтвердил control syntax, architecture/ownership compatibility, H0.2 machine checkpoint regression, V0-S1 networked checkpoint regression и PC0 auditors.

Это **не** заменяет Godot 4.7.1 double Windows runtime evidence.

## 13. Известный CRITICAL availability gap до acceptance

Transient target reservation специально не является canonical/durable state.

Следовательно сценарий:

```text
target PREWARMED ACK sent
-> target process restarts
-> reservation memory lost
-> source crosses before learning about restart
-> source retires writer
-> target receives FAST_COMMIT without reservation
```

в текущем candidate fail-closed отклоняется как:

```text
SM0_P4_FAST_COMMIT_WITHOUT_PREWARM
```

Это сохраняет single-writer safety, но handoff availability не восстанавливается автоматически.

P4 нельзя принимать, пока fault/restart experiment не определит и не докажет recovery policy. Не следует скрывать этот сценарий автоматическим dual-writer rollback.

## 14. Что не изменялось

P4 candidate не реализует:

- NX4/NX5 convergence;
- исправление stop-and-wait movement;
- P5 cross-authority projections;
- third authority;
- nested zones;
- generic object handoff;
- production World Directory;
- NATS/JetStream;
- distributed Matter mutation.

## 15. Следующий gate

До изменения статуса с `IMPLEMENTED CANDIDATE` нужны фактические Windows результаты exact HEAD:

1. P4 local acceptance;
2. legacy `-Final` regression;
3. P4 controlled WAN matrix;
4. сравнение p50/p95 с P3.1 baseline;
5. target-restart/fault experiment;
6. independent CRITICAL review.
