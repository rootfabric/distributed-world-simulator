# SM0-H2.4 — ACTIVE OWNER ACK DURABILITY

Статус: Design Brief / bounded SM0 lab

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`

База дизайна: H2.3 runtime PASS на `c702b8987601d2dfa4e19a41905ce54751ef9b25`.

## Цель

Доказать crash recovery единственного активного writer вне handoff.

Критический контракт:

> Успешный gameplay ACK не должен подтверждать состояние, которое новый process потеряет после crash.

Для H2.4 минимальный executable case — `MOVE_ACK`.

## Crash point

Первый accepted movement на active authority A:

1. canonical movement применён;
2. exact player position / velocity / input sequence находятся в canonical service;
3. recovery snapshot `ACTIVE_OWNER` записан и атомарно переименован;
4. `MOVE_ACK` ещё не отправлен;
5. process A принудительно уничтожается;
6. новый A поднимается из exact generation;
7. клиент повторяет тот же outstanding MOVE;
8. новый A rebind'ит exact old client session без повторного применения уже durable input;
9. клиент получает successful ACK и продолжает движение/handoff.

## Почему H2.2/H2.3 недостаточно

H2.2 сохраняет `TARGET_COMMITTED` handoff decision.

H2.3 сохраняет `SOURCE_RETIRED` handoff decision.

Между handoff'ами текущий active owner может принять много movement ACK. Без отдельной durability boundary crash способен вернуть player к более старому snapshot.

## Canonical truth

Player truth остаётся только в `NetworkedGameplayService` / `PlayerRegistry`.

SM0 snapshot хранит:

- существующий `gameplay_state`;
- существующий `gameplay_replay_state`;
- directory;
- protocol metadata, необходимое для transport recovery.

SM0 не создаёт вторую position/velocity truth.

## Новый phase

`ACTIVE_OWNER`

Protocol metadata:

- logical player id;
- player entity id;
- transport session id;
- client IP/UDP port;
- ownership epoch на момент durable ACK boundary;
- last input sequence;
- directory checksum/epoch через существующий directory snapshot.

Canonical durable export по существующему контракту очищает transport session. Поэтому session id хранится только как recovery routing metadata, а не как canonical gameplay state.

## Write-before-ACK

При включённом recovery mode:

- `JOIN_ACK` — persist `ACTIVE_OWNER` before send;
- accepted `MOVE_ACK` — persist `ACTIVE_OWNER` before send;
- `ACTIVATE_ACK` — persist `ACTIVE_OWNER` before send.

Это intentionally conservative SM0 implementation. Производительная реализация в будущем может использовать WAL/group commit, но ACK durability semantics должна остаться той же.

## Recovery of outstanding movement

После restore canonical player disconnected, session cleared.

Первый exact packet от сохранённого client endpoint/session выполняет controlled rebind.

Если `input_sequence == durable last_input_sequence`, это retry уже применённого durable MOVE:

- движение повторно НЕ применяется;
- возвращается current canonical player state.

Если `input_sequence > durable last_input_sequence`:

- session rebind;
- movement выполняется один раз с новым canonical ownership epoch;
- результат становится durable до ACK.

Неправильный endpoint/session/player identity не получает recovery privilege.

## Invariants

- один writer;
- player entity id неизменен;
- directory owner после active-owner restart тот же;
- recovered canonical position не откатывается относительно persisted generation;
- duplicate durable input не применяется второй раз;
- ownership epoch может увеличиться только из-за controlled rebind;
- чужой session/endpoint не может захватить recovered player;
- нет second player truth.

## Acceptance

Focused regression должен доказать:

- ACTIVE_OWNER snapshot validation;
- restore exact generation;
- disconnected canonical restore;
- exact session recovery eligibility;
- duplicate durable sequence returns current state without reapply;
- next sequence applies exactly once;
- identity/position continuity.

Windows process gate:

`RUN_V0_SM0_ACTIVE_OWNER_CRASH_ACCEPTANCE.ps1`

Должен реально выполнить `Stop-Process -Force` после `ACTIVE_OWNER` persistence и до first movement ACK, поднять новый PID и затем завершить handoffs.

Initial: 2 handoffs.

Final: 6 handoffs.

## Не входит

- simultaneous crash A+B;
- disk loss;
- OS/kernel power-loss fsync proof;
- distributed lease/consensus under network partition;
- production optimization persistence throughput.
