# SM0-H3.5 — dual-authority outage after durable target activation, before ACTIVATE_ACK observation

Дата: 2026-08-15

Ветка: `feature/sm0-two-authority-seamless-handoff-lab`

Статус: branch-local experimental design.

## Цель

Проверить следующий boundary после H3.4: transaction уже committed и source tracking может быть завершён в живом процессе, client уже переключился на target и отправил `CLIENT_ACTIVATE`, target уже durable зафиксировал `ACTIVE_OWNER`, но successful `ACTIVATE_ACK` ещё не дошёл до client.

После этого оба authority process должны быть потеряны почти одновременно, а тот же client process должен продолжить незавершённую activation без смены identity, второго target commit и второго crossing.

## Почему это отдельный failure class

H3.4 заканчивается до наблюдения commit decision client-ом. H3.2 начинается уже после завершённого crossing и durable movement active owner.

Между ними остаётся activation window:

1. B уже `TARGET_COMMITTED`;
2. A получил COMMITTED ACK и отправил redirect;
3. client отправил `CLIENT_REDIRECT_ACK` source и переключил socket route на B;
4. source может уже очистить `_source_transfer` в RAM;
5. client отправил `CLIENT_ACTIVATE`;
6. B rebind/activate state уже выполнен;
7. перед successful `ACTIVATE_ACK` ActiveRecovery обязан durable сохранить `ACTIVE_OWNER`;
8. ACK намеренно удерживается;
9. client остаётся `ACTIVATING` с outstanding exact ACTIVATE request.

В этот момент total outage должен проверить композицию transaction durability + active-owner durability.

## Expected durable viewpoints перед outage

### A / source

Живой runtime уже может иметь:

- `SM0_SOURCE_REDIRECT_ACKNOWLEDGED(T)`;
- `SM0_SOURCE_TRANSFER_COMPLETE(T)`;
- writer count = 0.

Но latest durable checkpoint A допустимо остаётся `SOURCE_RETIRED(T)`, потому что завершение source tracking само по себе не создаёт нового gameplay ownership state.

После restart A поэтому может снова восстановить pending `SOURCE_RETIRED(T)` и повторить COMMIT/redirect. Это должно быть безопасным idempotent replay, а не resurrect старого writer.

### B / target

Перед successful `ACTIVATE_ACK` обязательно существует durable:

- phase `ACTIVE_OWNER`;
- directory owner = B;
- same player entity id;
- target session id;
- client endpoint;
- ownership epoch;
- last input sequence / state revision;
- committed transfer T остаётся в snapshot.

## Fault profile

`h3-activation-dual-outage-before-ack-v1`

Fault применяется только к B и только к successful `ACTIVATE_ACK`:

1. выполнить established `_ensure_active_owner_persisted_for_ack(...)`;
2. убедиться, что durable phase = `ACTIVE_OWNER`;
3. emit deterministic crash point `DUAL_OUTAGE_AFTER_ACTIVE_OWNER_PERSIST_BEFORE_ACTIVATE_ACK`;
4. suppress successful `ACTIVATE_ACK` до external kill.

COMMIT, COMMITTED ACK и HANDOFF_REDIRECT для H3.5 не подавляются.

## Process gate

Default: 2 handoffs.

Final: 6 handoffs.

Перед kill supervisor обязан доказать для exact transfer T:

- target commit произошёл ровно один раз;
- source наблюдал target commit;
- source получил redirect ACK и завершил transfer tracking;
- client ещё не имеет `SM0_CROSSING_COMPLETED`;
- B emit `SM0_TARGET_ACTIVATED(T)`;
- B durable `ACTIVE_OWNER` существует;
- B successful `ACTIVATE_ACK` был suppressed после persistence;
- client PID жив и остаётся тем же.

Затем:

- kill A и B с request gap <= 500 ms;
- доказать zero-authority interval;
- client остаётся жив;
- restart B и A из тех же recovery dirs.

После restart:

- B восстанавливает exact `ACTIVE_OWNER` generation;
- A не становится writer; если он восстанавливает `SOURCE_RETIRED(T)`, его replay COMMIT/redirect должен быть идемпотентным;
- client retry того же ACTIVATE должен завершиться на B;
- ровно один `SM0_CROSSING_COMPLETED` для T;
- никакого второго `SM0_TARGET_AUTHORITY_COMMITTED(T)`;
- никакой identity mutation;
- последующие handoffs продолжаются до requested count.

## Fail-closed invariants

Любое из следующего = FAIL:

- crossing произошёл до outage;
- B не имел durable ACTIVE_OWNER до outage;
- A writer после recovery;
- duplicate target import/commit для T;
- client PID изменился;
- player identity изменилась;
- directory epoch откатился/разошёлся;
- recovered B не способен завершить exact outstanding activation;
- source replay вызывает invariant violation;
- финальное число handoff не совпадает с requested.

## Scope limits

H3.5 не доказывает:

- client process crash одновременно с authority outage;
- потерю/повреждение durable media;
- network partition с двумя одновременно живыми competing writers;
- quorum/consensus между replicas;
- production HA или V0-S1 acceptance.
