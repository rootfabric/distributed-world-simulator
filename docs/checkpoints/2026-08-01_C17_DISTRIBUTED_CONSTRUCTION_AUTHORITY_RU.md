# C17 — Distributed Construction Authority

**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C16, commit `a4376cd`
**Рекомендуемая ветка:** `feature/c17-distributed-construction-authority`

## Цель

Интегрировать строительные aggregates с горизонтальным spatial-server layer, сохранив главный инвариант:

```text
one ConstructAggregate
→ one authoritative owner server
→ one authority epoch
→ zero concurrent writers
```

Соседние серверы держат только read-only projections. Смена владельца выполняется через explicit migration fence и checksum-pinned handoff.

## Authority record

`ConstructionAuthorityRecord` закрепляет:

- construct ID;
- owner server и spatial cell;
- authority epoch;
- ACTIVE/MIGRATING/TAKEOVER_PENDING state;
- migration fence;
- section coordinator;
- read-only replica servers;
- owner lease expiration tick;
- current construct checksum;
- checksum записи.

Epoch начинается с 1 и увеличивается при migration/takeover. Обычная команда не может менять owner или epoch.

## Owner routing

`ConstructionDistributedCommand` оборачивает существующую C12 command и pin-ит expected owner и authority epoch.

```text
entry server
→ authority registry lookup
→ owner server
→ existing C12 gateway
→ existing C3/C9/C11 authoritative process
```

Не-owner сервер никогда не выполняет mutation локально. Он только forward-ит команду owner. Exact retry использует C12 terminal command identity.

## Migration fence и handoff

```text
ACTIVE epoch N
→ begin migration
→ MIGRATING fence: все новые writes запрещены
→ export construct state + terminal operations
→ install on target
→ commit migration
→ ACTIVE epoch N+1 on target
```

Handoff переносит terminal operations. Поэтому уже принятая до migration команда может быть повторена после смены owner: target возвращает exact replay, не выполняя второй commit.

Abort до commit снимает fence и оставляет исходного владельца.

## Read-only replicas и section coordination

Neighbor replica хранит:

- owner server;
- authority epoch;
- construct checksum;
- JSON-safe state bundle;
- last update tick;
- `READ_ONLY` mode.

Replica API не имеет write capability. Для больших зданий добавлена `ConstructionAuthoritySectionProjection`: section coordinator остаётся owner/coordinator aggregate, а server пространственной секции получает только read-only projection.

## Cross-zone split и material movement

После принятого C9 split child aggregate может быть зарегистрирован сразу на другом zone server. Parent сохраняет своего owner; child получает отдельный authority record и epoch.

`ConstructionCrossZoneItemTransfer` pin-ит exact item identities, source/target constructs, servers, cells, operation ID и source authority epoch. C17 только авторизует маршрут; реальное перемещение items по-прежнему выполняется C2B/M0 transaction.

## Owner failure и takeover

Takeover разрешён только если:

- owner endpoint недоступен;
- owner lease истёк;
- target endpoint доступен;
- target имеет актуальную read-only replica;
- cluster tick совпадает с проверяемым tick.

Takeover импортирует replica state, увеличивает epoch и fence-ит старого owner. Команды со старым epoch после takeover отклоняются.

## Persistence

Сохраняются:

- authority registry;
- все read-only replicas;
- cluster tick;
- checksums.

Server endpoints и runtime transports не сериализуются. После restart они регистрируются заново, затем загружается authority state.

## Проверенный vertical slice

Три сервера `alpha`, `beta`, `gamma` и construct на границе cells:

1. Команда приходит на beta, forward-ится owner alpha и commit-ится ровно один раз.
2. Retry через gamma возвращает exact replay.
3. Migration alpha → beta включает fence, перенос state/terminal operations и увеличивает epoch `1 → 2`.
4. Retry старой принятой команды после migration возвращается target beta как cross-epoch replay без второго commit.
5. C9 split child регистрируется на gamma; parent остаётся на beta.
6. Exact item transfer beta → gamma проходит authority authorization.
7. Beta падает; до lease expiry takeover запрещён.
8. После expiry gamma принимает ownership с epoch `3` из replica.
9. Старые epoch-2 commands отклоняются; новые routes идут на gamma.
10. Persistence/restart сохраняет records, replicas и terminal replay behavior.

## Focused acceptance

```text
C17 contracts:    PASS — 59 assertions
C17 integration:  PASS — 66 assertions
C17 total:        PASS — 125 assertions
Editor parse:     PASS
```

Локально повторно пройдены C1–C8 и C10–C16. Общий локальный профиль вместе с C17: `2798 assertions, PASS`.

Ожидаемый полный world profile:

```text
135/135 tests
138 steps
```

## Ограничения vertical slice

- transport является абстрактным endpoint interface; NATS/real RPC wiring относится к network adapter layer;
- migration переносит JSON-safe construct state, но production aggregate extraction/import должен использовать существующий M0 storage adapter;
- один небольшой aggregate не делится между несколькими writers;
- section servers не выполняют локальные writes;
- distributed transaction между двумя independent owners не вводится: cross-zone item transfer остаётся одной C2B/M0 operation с выбранным coordinator;
- geo-replication, quorum consensus и multi-region disaster recovery относятся к C22 hardening.
