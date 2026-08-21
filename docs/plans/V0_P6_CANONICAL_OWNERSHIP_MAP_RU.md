# V0 P6.1 — Canonical Ownership Map

Статус: **CONTROL / AUDIT REPAIR CANDIDATE — NO RUNTIME AUTHORITY**

P6 checkpoint: `V0_P6_PERSISTENT_SHARED_OUTPOST`

Stacked control base: `715370c2d81e5129095412fdf68e34eee1f71bdf`

Canonical main anchor: `1d9de3c479c60045d613660b2a5c5db0374963f8`

Accepted P5 product lineage / P6 runtime execution base: `491ca7d058690d3de5fcea5e41aaee230a31b3ab`

Machine map: `config/control/harness/v0-p6-canonical-ownership-map.v1.json`

Repair finding: `P6.1-R-001` against failed review HEAD `9e4a0cebfe4801e075b7f91774e55173b5143619`.

## Цель

P6.1 не создаёт новую подсистему. Его задача — до первой runtime-мутации зафиксировать, **кто уже владеет каждой канонической истиной**, и где P6 разрешено только композировать или адаптировать существующий owner API.

Главный критерий выхода:

`ZERO_UNRESOLVED_DUPLICATE_TRUTH`

P6 является product-composition checkpoint. Он не становится новым foundation owner.

## Fail-closed closed model — Repair R2

После finding `P6.1-R-001` карта больше не считается открытым набором domains.

Machine contract теперь требует:

- exact allowlist из 15 P6.1 domains;
- отсутствие missing domains;
- отсутствие extra/unknown domains;
- отсутствие duplicate domain IDs;
- для каждого registry-backed domain — **точный ожидаемый registry key**, а не любой существующий key;
- domain без registry key запрещён, если он не входит в пять явных non-registry contracts;
- каждый non-registry exception/composite/donor имеет точный разрешённый owner/classification/authority contract;
- полный `forbidden_second_truths` проверяется как exact set, а не как набор отдельных presence assertions;
- `ZERO_UNRESOLVED_DUPLICATE_TRUTH` вычисляется regression-кодом из closed model; записанные `[]` в exit gate — только evidence snapshot, а не источник истины.

Пять допустимых non-registry contracts:

1. `RESOURCE_MINING_GAMEPLAY` — accepted P3 gameplay rule, canonical output остаётся `ITEM`.
2. `PERSISTENT_SHARED_OUTPOST_COMPOSITION` — composition existing owners, `creates_canonical_store=false`.
3. `EDGE_GATEWAY_COMMAND_SESSION_ROUTING` — NX+Authority boundary, `authoritative=false`.
4. `PRODUCTION_OWNERSHIP_DIRECTORY_AND_DOMAIN_TRANSFER` — post-P6 SM1 donor boundary, `production_active_in_p6=false`.
5. `SEAMLESS_RESEARCH_AND_MRPF` — research-only donor, `becomes_product_base=false`.

Любой шестой unmapped domain должен делать Project Control RED.

Regression содержит adversarial proofs, в том числе исходный reviewer counterexample:

```text
OUTPOST_OPERATION_LEDGER
canonical_owner = P6
status = RESOLVED
unresolved_duplicate_truth = []
```

Даже если автор одновременно пытается добавить этот domain в локальный JSON allowlist/non-registry contracts, regression сравнивает его с независимым frozen expected model и обязан вернуть violation.

Также проверяются обходы:

- удалить registry binding у Item Graph;
- перепривязать Item Graph к другому валидному foundation key;
- превратить outpost composition в `P6_OUTPOST` canonical owner/store.

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

## Что именно доказывает P6.1

P6.1 доказывает закрытость **control ownership model до runtime dispatch**. На этом этапе runtime P6 ещё не разрешён и не существует как active mutation line.

P6.1 не объявляет, что будущий runtime-код автоматически доказан корректным навсегда. После activation каждый runtime candidate остаётся обязан выполнить frozen Work Order predicates, в том числе:

- `V0_P6_CANONICAL_OWNERSHIP_MAP_PASS`;
- `V0_P6_ZERO_DUPLICATE_CANONICAL_TRUTH_PASS`;
- fresh Reviewer/Verifier gates.

То есть closed ownership model является нормативной границей для runtime implementation, а окончательное отсутствие duplicate runtime truth всё равно должно быть доказано на exact реализованном P6 HEAD. P6.1 не подменяет этот будущий runtime proof.

## Fail-closed правила

Любое из следующего останавливает P6 и требует возврата к соответствующему foundation owner:

- неизвестный/unmapped ownership domain → запрещено;
- смена expected registry binding → запрещено;
- новый network protocol/prediction/reconciliation authority → `NX`;
- новый canonical ownership/directory mechanism → post-P6 `SM1/AUTHORITY`;
- новый Item Graph/inventory/equipment store → запрещено;
- новый Construction truth → запрещено;
- новый persistence/recovery owner → запрещено;
- новый transaction/dedup engine → запрещено;
- gateway/WARM/projection получает право mutation → запрещено;
- research branch предлагается как product base → запрещено.

## Evidence semantics

Machine map фиксирует `control_audit_result = PASS_CANDIDATE`, но:

- `derivation_mode = MACHINE_DERIVED_FROM_CLOSED_MODEL`;
- `declared_arrays_are_authority = false`;
- `completion_bearing_harness_event_emitted = false`;
- `runtime_authority_granted = false`;
- P6 mutation lease не вращается этим изменением;
- production SM1 не активируется;
- P6.1 считается завершённым только после fresh exact-head Project Control, fresh independent review и последующей materialization в разрешённом activation flow.
