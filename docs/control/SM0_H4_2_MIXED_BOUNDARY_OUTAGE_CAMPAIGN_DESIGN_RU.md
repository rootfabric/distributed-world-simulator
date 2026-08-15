# SM0 H4.2 — mixed-boundary dual-authority outage campaign

Статус: **BRANCH-LOCAL EXPERIMENTAL DESIGN**.

Это не global acceptance, не production acceptance и не разрешение включать `SERVER_HANDOFF` в V0-S1. Cross-server authority остаётся CRITICAL-risk областью.

## Цель

После H3.3/H3.4/H3.5 и H4.1 уже отдельно доказаны:

- durable `TARGET_PREPARED` перед PREPARED ACK;
- durable `SOURCE_RETIRED` до первого реального COMMIT send;
- durable `TARGET_COMMITTED` до COMMITTED ACK;
- durable `ACTIVE_OWNER` до ACTIVATE_ACK;
- повторяющиеся alternating activation-boundary total outages в одной client session.

H4.2 проверяет другую вещь: способен ли один и тот же client переживать **разные recovery boundary подряд**, когда transaction state каждого authority много раз переходит между prepared/retired/committed/active состояниями и направление handoff чередуется.

## Campaign matrix

Для target directory epoch используется deterministic трехфазный rotation:

- epoch 2 -> `INFLIGHT_RETIRE`;
- epoch 3 -> `COMMIT_DECISION`;
- epoch 4 -> `ACTIVATION`;
- epoch 5 -> `INFLIGHT_RETIRE`;
- epoch 6 -> `COMMIT_DECISION`;
- epoch 7 -> `ACTIVATION`.

То есть final 6-handoff campaign имеет exact matrix:

1. A -> B, H3.3-class boundary: source `SOURCE_RETIRED`, target `TARGET_PREPARED`, COMMIT/redirect ещё не завершены;
2. B -> A, H3.4-class boundary: target `TARGET_COMMITTED`, source `SOURCE_RETIRED`, commit decision ещё не наблюдён client;
3. A -> B, H3.5-class boundary: target `ACTIVE_OWNER`, ACTIVATE_ACK ещё не доставлен client;
4. B -> A, H3.3-class boundary;
5. A -> B, H3.4-class boundary;
6. B -> A, H3.5-class boundary.

Таким образом каждый тип boundary проверяется в обоих направлениях.

## Fault profile

Новый profile:

`h4-mixed-boundary-dual-outage-v1`

Profile не вводит новый recovery algorithm. Он только выбирает fault boundary по **target directory epoch** и использует уже существующие write-before-ACK guarantees.

Boundary function:

`(target_epoch - 2) mod 3`

- `0` -> `INFLIGHT_RETIRE`;
- `1` -> `COMMIT_DECISION`;
- `2` -> `ACTIVATION`.

## Replay rule

Fault должен срабатывать только на fresh transition текущего ownership epoch.

После restart replay предыдущего transition обязан пройти normal path:

- restored source `SOURCE_RETIRED(T)` может повторить exact COMMIT/redirect;
- restored target `TARGET_COMMITTED(T)` может ответить на repeated COMMIT без нового import/commit;
- restored `ACTIVE_OWNER` может ответить на repeated activation.

Для этого profile должен различать fresh transition и recovery replay, а не повторно подавлять ACK/send одного и того же transfer.

## Required state at each outage

### INFLIGHT_RETIRE

До kill:

- source durable phase: `SOURCE_RETIRED(T)`;
- target durable phase: `TARGET_PREPARED(T)`;
- target writer_count: `0`;
- client completed crossings: previous cycle count only;
- same transfer id на обеих сторонах.

После restore:

- target restores `TARGET_PREPARED`;
- source restores `SOURCE_RETIRED`;
- exact COMMIT replays;
- target commits exactly once;
- client completes current crossing exactly once.

### COMMIT_DECISION

До kill:

- source durable phase: `SOURCE_RETIRED(T)`;
- target durable phase: `TARGET_COMMITTED(T)`;
- target writer_count: `1`;
- successful `PLAYER_HANDOFF_COMMITTED` intentionally suppressed;
- client current crossing ещё не завершён.

После restore:

- target restores existing commit decision;
- source restores retired transfer and repeats COMMIT;
- repeated COMMIT must not create second `SM0_TARGET_AUTHORITY_COMMITTED` or second target decision;
- client completes crossing exactly once.

### ACTIVATION

До kill:

- source durable phase: `SOURCE_RETIRED(T)`;
- target durable phase: `ACTIVE_OWNER`;
- source live tracking may already be complete;
- fresh successful `ACTIVATE_ACK` intentionally suppressed;
- client current crossing ещё не завершён.

После restore:

- target restores `ACTIVE_OWNER`;
- stale source recovery replay remains idempotent;
- repeated activation rebinds existing player/session state;
- client completes crossing exactly once.

## Global campaign invariants

На всём H4.2 run обязательны:

- один client PID от старта до конца campaign;
- exactly one completed crossing per cycle;
- unique transfer id per handoff;
- target authorities alternate B/A;
- directory epoch progresses contiguously from 1 to `handoffs + 1`;
- no identity changes;
- no dual writer observation;
- no `SM0_COMMIT_WITHOUT_PREPARE`;
- no duplicate target import/commit;
- no recovery generation rollback;
- после каждого outage оба authority process действительно заменяются новыми PID;
- kill request gap <= 500 ms;
- client остаётся жив в zero-authority interval.

## Acceptance sizes

DEFAULT:

- `3` handoffs / `3` total outages;
- boundaries: `INFLIGHT_RETIRE -> COMMIT_DECISION -> ACTIVATION`;
- directions: A->B, B->A, A->B.

FINAL:

- `6` handoffs / `6` total outages;
- boundaries: full two-direction matrix;
- target sequence: B,A,B,A,B,A;
- expected final directory epoch: `7`.

## Scope

H4.2 — branch-local stress/composition evidence. Даже successful H4.2 не означает production/global acceptance server handoff и не меняет V0-S1 stop-before policy.