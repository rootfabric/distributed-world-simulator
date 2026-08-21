# V0 — Current Primary Work Map

Статус: **PRIMARY WORK MAP CANDIDATE R3 / PRE-P6 EDGE GATEWAY FOUNDATION**

После formal P5 acceptance текущая работа V0 теперь идёт не в P6 runtime, а в обязательный pre-P6 Gateway foundation.

Нормативный текущий execution plan:

`docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md`

Связанные документы:

- `docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`
- `docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`
- `config/control/harness/v0-edge-gateway-fabric-test-plan.v1.json`
- `config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`
- исторический detailed P6 base: `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md`
- Gateway architecture overlay: `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_R2_GATEWAY_OVERLAY_RU.md`

При конфликте по **порядку выполнения** этот current map и `V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md` имеют приоритет.

Canonical roadmap main anchor:

`1d9de3c479c60045d613660b2a5c5db0374963f8`

Future P6 product base остаётся:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

## Current route

```text
P5 ACCEPTED
    |
    v
PRE-P6 EDGE GATEWAY FOUNDATION
    |
    v
EG0 contracts / DTO / fixtures
    |
    v
EG1 Client -> Gateway -> Server A
    |
    v
EG2 Auth / Session / Placement
    |
    v
EG3 Shared multiplexed Gateway->Server tunnel
    |
    v
EG4 Projection aggregation through one client connection
    |
    v
EG5 Multi-Gateway nearest healthy Edge selection
    |
    v
EDGE_GATEWAY_FOUNDATION_ACCEPTED
    |
    +-----------------------------+
    |                             |
    v                             v
refresh P6 control           EG6 A<->B backend pivot
activate P6 runtime          EG7 Gateway rehome
P6.1 -> P6.11               EG8 WAN faults
    |                        EG9 scale/fairness/soak
    +-------------+---------------+
                  |
                  v
             P6 ACCEPTED
                  |
                  v
             ACTIVATE V0-SM1
                  |
                  v
Production Edge Gateway + Directory + A/B
                  |
                  v
real seamless A<->B behind one WorldConnection
                  |
                  v
                 P7
                  |
                  v
                 P8
```

## Hard sequencing rule

```text
P6 runtime mutation == FORBIDDEN
until
EDGE_GATEWAY_FOUNDATION_ACCEPTED
```

Pre-P6 cutoff строго:

```text
EG0 + EG1 + EG2 + EG3 + EG4 + EG5
```

EG6-EG9 не блокируют начало P6 и продолжаются параллельно после P6 activation.

## Edge Gateway baseline

```text
Client -> nearest healthy Edge Gateway
Edge Gateway -> current ACTIVE authority
Edge Gateway -> projection sources
```

Hard invariant:

```text
client_active_world_transports == 1
```

Client не получает simulation-server endpoint и не координирует server handoff.

## Shared backend links

Gateway->Server baseline:

```text
1..K physical links per GatewayInstance <-> ServerInstance
many logical player sessions multiplexed over those links
```

EG3 обязан доказать минимум два клиента на одном physical backend tunnel с:

- no cross-session leakage;
- bounded per-session queues;
- fairness/backpressure;
- disconnect одного клиента без teardown для остальных.

## Projection baseline

```text
Authority A ACTIVE ------\
Projection B -------------> Gateway -> same client WorldConnection
Macro projection --------/
```

Direct `ProjectionPublisher -> Client` connections не являются V0 baseline.

## Multi-Gateway selection

Gateway выбирается по healthy network score, а не только по географии.

Минимум учитываются:

- RTT;
- jitter;
- loss;
- health;
- capacity/load hint.

Routine future A->B world handoff не требует Gateway rehome.

Gateway rehome при падении/перегрузке Edge — отдельный recovery event.

## Gateway authority boundary

Gateway маршрутизирует, мультиплексирует и агрегирует сеть, но не владеет:

- PlayerId / PlayerEntityId truth;
- Item Graph / Inventory / Equipment;
- Construction;
- persistence;
- OperationId dedup truth;
- authority ownership / AuthorityEpoch;
- canonical mutation authorization.

## P6 control warning

PR #182 и #184 являются stale относительно нового mandatory pre-P6 gate.

Они не должны давать P6 runtime authority до:

```text
EDGE_GATEWAY_FOUNDATION_ACCEPTED
```

После acceptance они должны быть refresh/rebase/replaced так, чтобы новый P6 Work Order прямо зависел от accepted Gateway foundation.

## Operator rule

Текущий next work:

```text
IMPLEMENT / REVIEW / VERIFY EG0 -> EG5
```

Не dispatch P6 runtime Implementer.
Не rotate V0 runtime mutation lease to P6.
Не создавать новый P6 runtime candidate до Gateway foundation acceptance.

Final rule:

```text
FIRST PROVE THE WORLD CONNECTION.
THEN BUILD P6 ON TOP OF IT.
```
