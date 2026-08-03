# C12 — Multiplayer Construction Acceptance

**Статус:** IMPLEMENTED CANDIDATE
**Рекомендуемая ветка:** `feature/c12-multiplayer-construction-acceptance`
**База:** C11 delivery поверх принятого C10; C11 ещё требует внешней приёмки.

## Цель

Доказать, что C3/C9/C11 operations безопасно выполняются несколькими клиентами через единую authoritative multiplayer boundary.

```text
client intent
→ strict multiplayer command
→ session/order check
→ permission epoch check
→ optimistic preconditions
→ existing C3/C9/C11 process
→ C2A/C2B authority
→ ordered event
→ client replicas
→ checksum convergence
```

## Реализованные контракты

- checksum-pinned permission grants;
- permission epoch, revoke и wildcard/exact construct scopes;
- reconnectable sessions с epoch и ordered sequence;
- commands для `BUILD_STAGE`, `EDIT_GEOMETRY`, `APPLY_DAMAGE`, `APPLY_REPAIR`;
- optional global generation и обязательный construct checksum precondition;
- terminal exact replay и command-ID conflict;
- contiguous event stream;
- full authoritative item+construct state bundle для acceptance convergence;
- client replica с gap/rollback/tamper rejection;
- gateway/session/permission persistence.

## Конкурентный сценарий

Два клиента получают один и тот же geometry snapshot. Первый edit проходит. Второй command с прежними generation/checksum отклоняется до domain mutation. Ни Item Graph, ни event stream не меняются.

## Reconnect и crash recovery

После disconnect session epoch увеличивается; команды старого epoch отклоняются. Reconnect возвращает missing ordered events. Если gateway падает после authoritative commit, но до event publication, повтор команды обнаруживает terminal domain operation, выполняет exact replay и публикует один event без второго commit.

## Permission lifecycle

Permission store использует монотонный epoch. После revoke/epoch advance команды со старым epoch отклоняются. После reconnect клиент получает новый epoch, но revoked grant больше не авторизует действие.

## Convergence

Каждый successful event pin-ит полный canonical bundle:

```text
server_generation
sorted ItemProjection list
sorted ConstructSnapshot list
checksum
```

Две replicas после catch-up обязаны иметь тот же bundle checksum, что и authoritative gateway.

## Граница этапа

C12 — acceptance boundary, а не production transport. На этом этапе нет ENet/NATS endpoint, delta compression, bandwidth optimization или distributed owner routing. Эти задачи относятся к C17/C18.
