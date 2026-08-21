# V0 P6.1 — Canonical Ownership Map

Статус: **CONTROL / AUDIT CANDIDATE — NO RUNTIME AUTHORITY**

P6 checkpoint: `V0_P6_PERSISTENT_SHARED_OUTPOST`

Stacked control base: `715370c2d81e5129095412fdf68e34eee1f71bdf`

Canonical main anchor: `1d9de3c479c60045d613660b2a5c5db0374963f8`

Accepted P5 product lineage / P6 runtime execution base: `491ca7d058690d3de5fcea5e41aaee230a31b3ab`

Machine map: `config/control/harness/v0-p6-canonical-ownership-map.v1.json`

## Цель

P6.1 не создаёт новую подсистему. Его задача — до первой runtime-мутации зафиксировать, **кто уже владеет каждой канонической истиной**, и где P6 разрешено только композировать или адаптировать существующий owner API.

Главный критерий выхода:

`ZERO_UNRESOLVED_DUPLICATE_TRUTH`

P6 является product-composition checkpoint. Он не становится новым foundation owner.

## Нормативная классификация

- `OWN` — существующий канонический owner сохраняет semantic/mutation authority.
- `ADAPT` — P6 может добавить узкий adapter/composition boundary, но обязан делегировать каноническому owner.
- `READ_ONLY_DONOR` — разрешено читать/портировать проверенные semantics/evidence, но donor не становится production owner/base.
- `FORBIDDEN_SECOND_TRUTH` — P6-private canonical store/oracle запрещён.

## Карта владельцев

| Область | Канонический owner | Роль P6 | Жёсткая граница |
|---|---|---|---|
| Development control | `MAIN/HARNESS` | consume authorization | runtime не может сам себя dispatch/accept |
| Account/session identity | `IAM` | `ADAPT` | peer/session id не становится player/entity id |
| Authority ownership/fencing | `AUTHORITY` | `ADAPT` | production Directory и A↔B switch остаются SM1 |
| Transport/replication/prediction/reconciliation | `NX` | `ADAPT` | foundation change fail-closed в NX |
| Item Graph/inventory/containers | `ITEM` | `OWN` | один Item Graph, без outpost-private inventory |
| Equipment/tools | `ITEM` + accepted P5 gameplay contract | `ADAPT` | P6 не создаёт private equipment truth |
| Construction | `CONSTRUCTION` | `OWN` | outpost не получает отдельную базу construct truth |
| Persistence/replay/recovery | `R3_M0_MW` | `ADAPT` | без P6-private save format/owner |
| OperationId/dedup/idempotency | `WT` → existing M0 semantics | `ADAPT` | без второго transaction coordinator/dedup ledger |
| ResourceMining gameplay | accepted `V0_P3` rule; output truth=`ITEM` | `ADAPT` | без отдельного resource balance |
| Persistent Shared Outpost | composition existing owners | `ADAPT` | **не** новый canonical OutpostService store |
| Edge Gateway-like routing | NX + Authority boundaries | `ADAPT` | routing не является ownership oracle |
| WARM/SHADOW | derived/read-only | `READ_ONLY_DONOR` | ноль mutation authority |
| Production Directory/domain transfer | `AUTHORITY`, post-P6 SM1 | `READ_ONLY_DONOR` | P6 готовит только совместимые contracts |
| Seamless Research / MRPF | research donor only | `READ_ONLY_DONOR` | wholesale merge/product ancestry запрещены |

## Что означает Persistent Shared Outpost

`Outpost` в P6 — это **устойчивая композиция**, а не новая база данных истины:

```text
Player identity/session
        |
        +--> accepted ResourceMining rule
        |        |
        |        v
        |     canonical ITEM resources
        |
        +--> canonical ITEM inventory/containers/equipment
        |
        +--> canonical CONSTRUCTION state
        |
        +--> existing durable persistence/replay/recovery
        |
        +--> current NX transport/replication
                 |
                 v
        two-client persistent playable view
```

Никакой `OutpostService` не имеет права хранить альтернативный canonical inventory, construct graph, equipment state, resource balance или recovery truth.

## Seam-ready граница

P6 обязан подготовить интерфейсы так, чтобы позже SM1 мог заменить topology/authority routing без переделки gameplay ownership:

- identity остаётся topology-neutral;
- OperationId проходит end-to-end;
- mutation admission может принимать authority/fence context, но P6 не создаёт Directory;
- PlayerAuthorityDomain closure может быть вычислена/перенесена через adapter, но ownership truth не дублируется;
- gateway-style entry point не принимает ownership decisions;
- WARM/SHADOW остаётся строго read-only.

Это позволяет после P6 acceptance подключить production SM1 над рабочим gameplay baseline, а не одновременно изобретать persistence, Item Graph, Construction и handoff.

## Fail-closed правила

Любое из следующего останавливает P6 и требует возврата к соответствующему foundation owner:

- новый network protocol/prediction/reconciliation authority → `NX`;
- новый canonical ownership/directory mechanism → post-P6 `SM1/AUTHORITY`;
- новый Item Graph/inventory/equipment store → запрещено;
- новый Construction truth → запрещено;
- новый persistence/recovery owner → запрещено;
- новый transaction/dedup engine → запрещено;
- gateway/WARM/projection получает право mutation → запрещено;
- research branch предлагается как product base → запрещено.

## Evidence semantics

Machine map намеренно фиксирует `control_audit_result = PASS_CANDIDATE`, но:

- `completion_bearing_harness_event_emitted = false`;
- `runtime_authority_granted = false`;
- P6 mutation lease не вращается этим изменением;
- production SM1 не активируется;
- P6.1 считается завершённым только после требуемого control review/integration и последующего Harness materialization в разрешённом activation flow.
