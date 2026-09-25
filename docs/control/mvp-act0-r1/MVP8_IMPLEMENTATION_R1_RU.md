# MVP8 — bounded connected interactive workload

## Dispatch

Пользователь явно поручил: «реализуй MVP8». Работа продолжается в существующем `V0-MVP-R1-WO-001`; новый Work Order и новый canonical owner не создаются.

```text
MVP7_PRODUCT_HEAD = ad48b24d8cde350db8c26adb958d9a0d62c6ff56
MVP7_PRODUCT_TREE = f306e84ebce87ea3644c60b5dd75779d7980f8bb
MVP7_CLOSURE_HEAD = eab67e7d9913de13dc696aa6e3ff9d267f7ceaa1
MVP_RECONNECT_AND_RESTART = VERIFIED
```

Parent Work Order остаётся `IN_PROGRESS`. Runtime/main merge и whole-MVP acceptance не разрешены.

## Problem statement

MVP1–MVP7 доказали отдельные свойства. MVP8 должен доказать один связанный live workload с повторными move/seam/dig/item/build, fresh reconnect одного клиента, затем planned server/world restart из того же canonical cut и продолжение без duplicate identities и unbounded queue/replay state.

## Selected design

1. `v0_mvp8_authority_process.gd` — orchestration поверх MVP7/MVP6 owners. Authority A использует Service7/SharedMatter7; checkpoint сохраняется существующими M6 recovery, MW5 Matter и M0/C17 exports.
2. `v0_mvp8_gateway_process.gd` — workload sequencing/counters; Gateway не владеет gameplay state.
3. `v0_mvp8_workload_client.gd` — реальный ENet client с fixed-tick/current-state evidence.
4. Integration driver: initial two-client workload → fresh reconnect A → quiescent checkpoint → остановка server stack → новые authority/gateway PID → recovery exact cut → два fresh client connection → post-restart workload.

Restart — только confirmed quiescent checkpoint restart. Arbitrary uncheckpointed power-loss не заявляется.

## Workload phases

### Phase A — pre-reconnect
- два клиента подключены через один Gateway;
- repeated fixed-tick movement;
- A делает A→B→A seam roundtrip;
- минимум два canonical dig/material operation;
- item/equipment/container operations;
- исходный MVP6 Construction BASE→ADD→REMOVE + replay.

### Phase B — reconnect inside workload
Original client A завершает acknowledged phase cut. Fresh process A создаёт новый ENet peer, получает CURRENT state и продолжает workload. B остаётся подключённым.

### Phase C — server/world restart
Gateway запрашивает quiescent checkpoint у authority A. Cut связывает Service7 durable gameplay/replay, M4 Item Graph, MW5 Matter generation, M0 Construction adapter export, C17 cluster export, Construction snapshot/terminal commands и input watermarks. Старые authority/gateway завершаются; новые PID открывают тот же cut.

### Phase D — post-restart continuation
Оба logical client подключаются новыми transport sessions и продолжают fixed-tick movement, seam traversal, new dig/material, item/container operation и повторный Construction mutation cycle.

## Deterministic workload budget

```text
logical rounds total                  = 12
pre-reconnect rounds                  = 4
post-client-reconnect rounds          = 4
post-server-restart rounds            = 4
required canonical digs               >= 4
required Construction mutation cycles >= 2
required seam crossings               >= 4
required fixed-tick receipts          >= 24 total

gateway operation fingerprints        <= 256
gateway ledger committed operations   <= 512
per-backend RPC sequence              <= 512
per-client RPC sequence               <= 512
input observations retained           <= 128 per actor
durable replay pending rows           <= 32
Construction terminal commands        <= 16
world/material stream advance         <= 64
```

Любое превышение лимита — failure, не eviction/retry workaround.

## Required predicates

- `MVP_BOUNDED_INTERACTIVE_WORKLOAD`
- `ONE_CONNECTED_TWO_CLIENT_GAMEPLAY_LOOP`
- `REPEATED_MOVE_SEAM_DIG_ITEM_BUILD_OPERATIONS`
- `ONE_CLIENT_RECONNECT_AND_CONTINUE`
- `SERVER_OR_WORLD_RESTART_AND_CONTINUE`
- `BOUNDED_QUEUES_AND_REPLAY_STATE`
- `NO_DUPLICATE_ITEM_OR_CONSTRUCTION_IDENTITIES`
- `RESPONSIVE_PLAYER_CONTROL_MAINTAINED`

## Canonical ownership

Не меняются существующие owners: SM1/M6/MVP7 gameplay, M4 Item Graph, MW5/P7 terrain/material, M0+C17 Construction, existing ENet/Gateway, M6/MVP7 recovery. MVP8 checkpoint manifest — composition receipt, не owner.

## Validation

Focused connected workload + negatives (wrong generation, stale session, replay conflict, duplicate identity, skipped reconnect, same peer, missing post-restart motion, bound overflow, stale digest), затем MVP3/MVP5/MVP6/MVP7 regressions, full world/core, post-build critique, Evidence Map, fresh Reviewer/Verifier и PC0.

## Non-goals

Arbitrary mid-write power loss, new persistence engine, new owner, new retirement policy, unrelated performance tuning, main merge и whole-MVP acceptance.

## Current state

`IMPLEMENTATION_IN_PROGRESS`. Этот brief не является evidence/verdict.
