# V0-SM1 — production A↔B seamless handoff execution plan

**Статус:** CONTROL CANDIDATE / POST-P6 ACTIVATION  
**База:** `main @ 9ade3233f8d9f16b77edcc8cf273fe8e649d5637`  
**Accepted predecessor:** `V0_P6_PERSISTENT_SHARED_OUTPOST`  
**Runtime branch after control acceptance:** `feature/v0-sm1-seamless-product-integration`  
**Risk:** `CRITICAL`

## 1. Цель

Перенести уже доказанные SM0 two-authority handoff semantics на современную P6 product lineage без merge исторической research-ветки и без второго gameplay truth.

Первый production SM1 должен доказать не arbitrary distributed world, а один жёстко ограниченный сценарий:

```text
2 graphical clients
        ↓
1 stable Edge Gateway endpoint per client
        ↓
Authority A ACTIVE
Authority B WARM
        ↓
A -> B ownership transfer
        ↓
Authority B ACTIVE
        ↓
B -> A return transfer
```

На всём пути сохраняются:

```text
logical_player_id
player_entity_id
input sequence
OperationId semantics
canonical Item Graph
canonical Construction/outpost truth
single persistence owner
```

И в каждый момент времени существует ровно один canonical writer.

## 2. Почему начинаем именно сейчас

P6 уже принят на `main` и содержит foundation, которого не было у раннего SM0:

- topology-neutral identity;
- exactly-once operation ledger;
- mutation admission boundary;
- gateway-ready command route;
- persistent shared outpost;
- destructive restart/recovery;
- WARM/SHADOW read-only compatibility;
- fault/race and repeat evidence.

SM0 отдельно уже доказал A↔B handoff, one-writer fencing и repeated crossings. Поэтому SM1 не должен заново проектировать handoff. Он должен выполнить минимальный semantic port на текущих владельцев P6/AUTHORITY/NX.

## 3. Сначала закрыть post-P6 control debt

До runtime dispatch обязательны четыре действия.

### 3.1 Formal P6 acceptance record

В main отсутствовал отдельный `V0-P6-...CHECKPOINT-ACCEPTED` record, несмотря на merge commit `9ade3233...` с явным `P6 ACCEPTED`.

Новый record должен зафиксировать:

```text
accepted runtime head = 7a77c048...
accepted product/main baseline = 9ade3233...
PR #212
all 26 predicates verified
P6.1-P6.11 review+verify PASS
owner-authorized runtime merge
```

### 3.2 Reconcile current work map

Старый pointer всё ещё говорит `PRE_P6_EDGE_GATEWAY_FOUNDATION`.

Новый canonical state:

```text
P6_ACCEPTED
    ↓
POST_P6_SM1_ACTIVATION
    ↓
V0_SM1_SEAMLESS_PRODUCT_INTEGRATION
```

### 3.3 Rotate mutation lease only after control acceptance

Control candidate может объявить intended successor, но runtime mutation остаётся false до:

```text
fresh independent control review PASS
→ merge control candidate to main
→ post-merge Project Control NON_RED
→ lease holder = V0_SM1
→ Director DISPATCHED event
```

### 3.4 EG5 pre-dispatch repair

Перед реальным handoff исправить две вещи в Edge locator:

1. `probe_failures` сейчас растёт как `n = n + n + 1`, а должен `n += 1`.
2. Hysteresis должен сравнивать fresh score нового кандидата с fresh score текущего gateway, а не с историческим `_last_primary_score`; outcome metadata обязана описывать фактически выбранный gateway.

Этот repair должен быть отдельным маленьким reviewed runtime PR. SM1 не должен прятать network repair внутри authority feature.

## 4. SM1.1 — donor/owner port map

Перед переносом кода составить executable mapping:

```text
SM0 synthetic concept                  -> current owner
---------------------------------------------------------------
logical player identity                -> P6 identity registry/current player owner
operation replay                       -> P6 operation ledger
mutation authorization                 -> P6 admission + AUTHORITY ownership evidence
shadow target                          -> P6 WARM/SHADOW adapter
client route                           -> accepted Edge Gateway route/session stack
items                                  -> canonical Item Graph
outpost/construction                   -> canonical Construction/P6 composition
persistence                            -> existing single persistence owner
```

Для каждого SM0 модуля результат должен быть одним из:

```text
PORT_SEMANTICS_ONLY
ADAPT_TO_CURRENT_OWNER
TEST_DONOR_ONLY
DROP_SYNTHETIC_OWNER
```

Запрещён результат `COPY_AS_NEW_CANONICAL_OWNER`.

Exit:

`SM0_DONOR_TO_P6_OWNER_MAP_PASS`

## 5. SM1.2 — authority transfer core

Первый runtime слой не должен знать UI, mining или конкретные Item/Construction операции.

Нужен generic transfer state machine:

```text
ACTIVE_A
  ↓ begin_transfer(transfer_id)
SOURCE_FROZEN
  ↓ build transfer manifest from current canonical state
TARGET_WARM_VALIDATED
  ↓ ownership linearization
DIRECTORY/OWNERSHIP_COMMITTED_B
  ↓ source capability revoked
SOURCE_RETIRED
  ↓ target activates higher epoch
ACTIVE_B
```

### Инварианты

```text
transfer_id stable
owner epoch monotonic
no second ACTIVE writer
source cannot write after ownership commit
WARM cannot write before activation
exact retry after lost success response converges to ALREADY_COMMITTED
future/stale-looking local tuple cannot self-authorize
```

### Negative tests

- A dies before ownership commit -> A remains canonical or transfer aborts cleanly;
- A dies immediately after ownership commit -> B reconstructs committed outcome;
- response lost after commit -> exact retry does not make second transition;
- B dies before activation -> no dual writer;
- old A restarts -> fenced;
- duplicate transfer request -> one commit;
- competing transfer ids -> at most one wins.

## 6. SM1.3 — Player Carrying Domain

Поверх generic transfer подключить player closure.

Transfer manifest содержит только необходимые derived/canonical references, не новый store:

```text
logical_player_id
player_entity_id
current authority epoch evidence
input sequence watermark
OperationId/replay continuity reference
player transform/reference-frame state
inventory/equipment references
construction/outpost relevance reference
```

После A→B должны быть byte/semantic-equal там, где identity immutable:

```text
logical_player_id before == after
player_entity_id before == after
next input sequence == previous + 1
replayed operation before/after == exactly once
```

Normal crossing никогда не вызывает:

```text
respawn
new player entity
inventory recreation
UI reset as canonical state
new OperationId namespace
```

## 7. SM1.4 — Gateway-preserving authority pivot

Клиент остаётся на одном Edge Gateway endpoint.

```text
Client
  |
  | same WorldConnection
  v
Gateway
  | ACTIVE -> A
  | WARM   -> B
```

Перед crossing target B должен быть подготовлен как WARM/read-only.

После ownership commit Gateway меняет routing role:

```text
A: ACTIVE -> DRAIN
B: WARM   -> ACTIVE
```

Gateway не решает, кто owner. Он применяет уже полученное authoritative routing evidence.

Hard test:

```text
client gateway_instance_id before == after
simulation server endpoint never exposed to client
mark_authority_handoff does not trigger edge re-selection
```

## 8. SM1.5 — composition with real P6 state

Когда transfer core зелёный, подключить реальный product loop.

Reference scenario:

```text
A ACTIVE
player mines ore
player equips tool
player modifies shared outpost
second client observes result

player approaches boundary
B becomes WARM
A -> B handoff

player uses inventory in B
player performs Construction mutation in B
second client observes result

B -> A handoff
server/client reconnect
same durable truth reconstructed
```

Проверки:

- ItemId не меняются;
- inventory quantities не теряются/не дублируются;
- equipment slot продолжает ссылаться на тот же canonical item;
- Construction revision не откатывается;
- outpost checksum сохраняет все accepted contributions;
- persistence owner остаётся единственным writer;
- operation replay до/после handoff возвращает тот же committed result.

## 9. SM1.6 — graphical acceptance

Минимальная topology:

```text
Gateway process
Authority A process
Authority B process
Graphical client A
Graphical client B
```

Обязательный операторский прогон:

1. Оба клиента входят в одну product session.
2. Игрок A выполняет P6 gameplay action под Authority A.
3. B-client видит тот же canonical result.
4. Игрок A идёт через boundary.
5. В логах видны WARM target и transfer_id.
6. Игрок продолжает движение/interaction уже под Authority B без respawn/reconnect screen.
7. IDs до/после совпадают.
8. Выполняется реальная Item/Construction operation под B.
9. Второй клиент видит результат.
10. Игрок возвращается B→A.
11. Disconnect/reconnect восстанавливает тот же persistent state.

Допускается на первом checkpoint:

```text
bounded visual correction
короткий transfer pause
неидеальная interpolation smoothness
```

Не допускается:

```text
identity change
split brain
lost/duplicate item
second Construction commit
crossing reconnect
canonical rollback
```

## 10. SM1.7 — brutal fault matrix

Перед acceptance обязательно прогнать:

| Сценарий | Требуемый результат |
|---|---|
| A crash до commit | transfer abort/old truth intact |
| A crash после ownership commit | B становится единственным допустимым writer |
| lost commit response | retry -> ALREADY_COMMITTED |
| stale A restart | FENCED |
| B crash до activation | zero dual writer |
| duplicate packets | exactly once |
| reorder | monotonic state/revision |
| two players cross simultaneously | independent transfer ids, no global split brain |
| Gateway connection jitter | authority truth unchanged |
| player reconnect after handoff | same identity + same durable P6 state |

После focused fault matrix:

```text
repeated A<->B crossings
full world/core regression
fresh Reviewer
fresh Verifier
checkpoint proposal
```

## 11. Acceptance критерий первого production seamless checkpoint

SM1 считается готовым к proposal только если одновременно:

```text
exactly_one_active_writer == true
identity_changes == 0
normal_crossing_reconnects == 0
split_brain == 0
duplicate_operations == 0
duplicate_items == 0
duplicate_construction_commits == 0
warm_writes == 0
stale_source_authorizations == 0
client_gateway_endpoint_changes == 0
```

И real P6 state действительно пережил:

```text
A -> B -> A
+ failure injection
+ reconnect
+ persistence reconstruction
```

## 12. Что идёт после

После static production SM1 acceptance можно развивать параллельно:

```text
EG6    ACTIVE/WARM multi-world backend pivot
EG6.5  real cross-world canonical effect commit
EG7    Gateway failure/rehome
EG8    WAN/CWIP fault profiles
EG9    scale/fairness/soak
```

А продуктовый train продолжает:

```text
SM1 ACCEPTED
  ↓
P7 bounded terrain mutation
  ↓
P8 first mobile construct
```

Dynamic split/merge и arbitrary load balancing не входят в первый SM1.
