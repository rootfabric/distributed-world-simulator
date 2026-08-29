# SM0 H4.3 — recovery-of-recovery одного и того же transfer

Статус: **BRANCH-LOCAL EXPERIMENTAL DESIGN**.

Это не global acceptance, не production acceptance и не разрешение включать `SERVER_HANDOFF` в V0-S1. Cross-server authority остаётся CRITICAL-risk областью.

## База

H4.3 начинается после зафиксированного H4.2 runtime evidence:

- branch: `feature/sm0-two-authority-seamless-handoff-lab`;
- base HEAD: `ed5d7d3d26c4ff33d707087fea91d33aba6f449f`;
- H4.2 tested runtime SHA: `3e95dd881e55784bfe15a9901e7d1fe9bac143f9`;
- H4.2 доказал mixed-boundary recovery между разными handoff transaction, но не повторный crash во время recovery одного и того же transaction.

## Цель

Проверить, что один exact handoff transfer `T` может продвинуть durable state через несколько recovery boot подряд, причём каждый промежуточный recovery снова прерывается simultaneous outage обоих authority до client-observed completion.

Проверяемая цепочка:

```text
fresh T
  source: SOURCE_RETIRED
  target: TARGET_PREPARED
  -> total outage #1

restore same T
  source replays COMMIT
  target advances to TARGET_COMMITTED
  -> total outage #2

restore same T
  source replays COMMIT/redirect idempotently
  client activates target
  target advances to ACTIVE_OWNER
  -> total outage #3

restore same T
  target restores ACTIVE_OWNER
  source restores SOURCE_RETIRED
  same client completes exactly one crossing for T
```

В отличие от H4.2, после outage #1 и #2 **не должен начинаться новый handoff transfer**. Все три outage относятся к одному и тому же `transfer_id`.

## Fault profile

Новый profile:

`h4-recovery-of-recovery-same-transfer-v1`

Для него используется отдельный H4.3 fault node. Он не изменяет canonical authority/recovery semantics и только подавляет конкретные outbound messages в зависимости от durable boot state.

### Stage 1 — PREPARED boundary

На fresh process source после durable `SOURCE_RETIRED`:

- `PLAYER_HANDOFF_COMMIT` подавляется;
- emit `SM0_H43_CRASH_POINT` stage `PREPARED`;
- target должен иметь durable `TARGET_PREPARED` для exact `T`;
- client crossing count остаётся `0`.

После total outage source recovery replay **не должен повторно подавляться**.

### Stage 2 — COMMITTED boundary

Target, который boot-нулся из exact `TARGET_PREPARED`, принимает replayed COMMIT:

- target canonical import/commit выполняется один раз;
- durable phase продвигается в `TARGET_COMMITTED`;
- успешный `PLAYER_HANDOFF_COMMITTED` ACK подавляется;
- emit `SM0_H43_CRASH_POINT` stage `COMMITTED`;
- source остаётся durable `SOURCE_RETIRED`;
- client crossing count остаётся `0`.

После следующего restart duplicate COMMIT должен быть idempotent и successful COMMITTED уже должен пройти дальше.

### Stage 3 — ACTIVE boundary

Target, который boot-нулся из exact `TARGET_COMMITTED`, после idempotent COMMIT/redirect принимает client activation:

- active ownership/session binding выполняется;
- `ACTIVE_OWNER` snapshot должен быть durably persisted write-before-ACK;
- `ACTIVATE_ACK` подавляется;
- emit `SM0_H43_CRASH_POINT` stage `ACTIVE`;
- source остаётся durable `SOURCE_RETIRED`;
- client crossing count всё ещё `0`.

После третьего restart target, boot-нувшийся из `ACTIVE_OWNER`, **не fault-ится повторно** и должен позволить тому же client завершить тот же crossing.

## Boot-state discrimination

H4.3 fault node должен различать fresh и recovery process по durable state, а не по внешнему счётчику supervisor-а:

- source fresh: `_recovery_restored == false` -> разрешён Stage 1 fault;
- source restored `SOURCE_RETIRED` -> replay COMMIT/redirect всегда пропускаются;
- target restored `TARGET_PREPARED` -> разрешён Stage 2 fault;
- target restored `TARGET_COMMITTED` -> разрешён Stage 3 fault;
- target restored `ACTIVE_OWNER` -> fault больше не разрешён.

Нельзя использовать process-local one-shot state как единственный источник стадии: каждый outage создаёт новые authority process.

## Exactness / invariants

Acceptance должна fail-closed проверять:

1. Один `transfer_id` для всех трёх outage одной chain.
2. Один client PID на всю chain.
3. До третьего recovery crossing count равен `0` для текущего T.
4. Stage 1 durable pair: source `SOURCE_RETIRED`, target `TARGET_PREPARED`.
5. Stage 2 durable pair: source `SOURCE_RETIRED`, target `TARGET_COMMITTED`.
6. Stage 3 durable pair: source `SOURCE_RETIRED`, target `ACTIVE_OWNER`.
7. Target generation строго продвигается между PREPARED -> COMMITTED -> ACTIVE_OWNER.
8. Source restore остаётся exact durable `SOURCE_RETIRED`; writer count `0`.
9. После Stage 1 recovery допускается ровно один canonical target commit/import для T.
10. После Stage 2 и Stage 3 recovery новый canonical target commit/import для T запрещён; duplicate replay только idempotent.
11. `SM0_COMMIT_WITHOUT_PREPARE` запрещён.
12. `SM0_INVARIANT_VIOLATION` запрещён.
13. После final restore crossing T завершается ровно один раз.
14. `player_entity_id` не меняется.
15. Directory epoch увеличивается ровно один раз на handoff, а не один раз на outage.
16. Client остаётся жив во всех zero-authority intervals.
17. Оба authority process действительно завершаются на каждом outage.

## DEFAULT

Один handoff `A -> B`, один exact transfer `T`, три sequential total outage:

`PREPARED -> COMMITTED -> ACTIVE -> completion`.

Expected final:

- outage: `3 / 3`;
- handoff: `1 / 1`;
- target sequence: `B`;
- final directory epoch: `2`;
- identity changes: `0`.

## FINAL

Две recovery chains в одной непрерывной client session:

1. `A -> B`: один T переживает PREPARED, COMMITTED, ACTIVE outage;
2. `B -> A`: новый T2 переживает ту же трёхступенчатую цепочку.

Expected final:

- outages: `6 / 6`;
- chains: `2 / 2`;
- handoffs: `2 / 2`;
- target sequence: `B,A`;
- final directory epoch: `3`;
- identity changes: `0`.

## Не входит в H4.3

- новый production recovery algorithm;
- изменение canonical Item Graph / gameplay truth;
- multi-client scale;
- server-to-server consensus;
- production/global acceptance;
- graphical P2 recovery lab.

После H4.3 runtime evidence следующий рекомендуемый checkpoint — P2 Graphical Recovery Lab, который визуально покажет те же durable phases и authority outages локально.
