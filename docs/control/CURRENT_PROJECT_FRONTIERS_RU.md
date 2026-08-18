# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Canonical main at this refresh:** `598e92bb29a147bf12208d8549ddecaa4c9781ab`  
**Architecture baseline:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Registry generation:** `80`  
**Control plane:** `PC0-2026-08-10-R1`  
**Harness base revision:** `H0-2026-08-11-R1`  
**Harness P-train amendment:** `H0-PTRAIN-2026-08-18-R1`

> Machine project-state truth remains `config/control/project-program-registry.v1.json`. Product-train succession rules are additionally owned by `config/control/harness/v0-product-train-policy.v1.json`.

## Главный продуктовый приоритет

Основная playable линия сейчас — V0/P.

```text
P0 playable frontier
→ P1 world items / containers
→ P2 reconnectable shared state
→ P3 resource mining
→ P4 real-resource Construction       ← CURRENT CLOSURE
→ P5 equipment / tools                 ← NOT ELIGIBLE YET
→ P6 persistent shared outpost         ← NOT ELIGIBLE YET
→ post-P6 seamless decision
→ V0-SM1 or explicit defer
→ P7 bounded terrain mutation
→ P8 first mobile construct / ship
```

P — последовательный product train. Следующий checkpoint не получает runtime dispatch до принятия предыдущего checkpoint и отдельной main-owned successor activation.

Подробные правила:

`docs/control/V0_P_PRODUCT_TRAIN_RULES_RU.md`

## Current P4 state

P4 runtime implementation завершён и заморожен.

Historical generation-80 activation/pre-runtime subject remains immutable provenance:

```text
47ff18cf603bbf98bb67f7f62962e050f8606542
```

Это dispatch/input snapshot, а не текущая runtime truth и не checkpoint acceptance claim.

Exact implementation/evidence target:

```text
2a6721cdf02fa1134c59d1ab98bb7b597c66821d
```

Fresh independent P4 Reviewer и Verifier ранее проверили этот exact runtime/evidence target. Последующие проблемы относятся к Harness/control closure, а не к новому P4 runtime scope.

Текущий closure repair:

```text
PR #127
branch: repair/v0-p4-closure-ledger-state-r1
candidate: 11969a954ceb9baab1b4a55cb2162fa1069fb0b2
```

Live-frontier routing repair уже интегрирован:

```text
PR #130 merged
main: 598e92bb29a147bf12208d8549ddecaa4c9781ab
```

Следующий P4 control path:

```text
confirm exact-main Project Control NON_RED after #130
→ rerun #127 Project Control against corrected main
→ integrate #127 only if exact reviewed subject remains valid
→ continue append-only P4 closure ledger
→ record remaining predicates
→ propose/accept V0_P4 checkpoint
→ only then activate P5
```

До этого момента P5 runtime mutation запрещён.

## Mutation lease

До H0.3 разрешён максимум один autonomous runtime mutation worker.

Сейчас lease остаётся fail-closed привязан к:

```text
program: V0
checkpoint: V0_P4_REAL_RESOURCE_CONSTRUCTION
branch: feature/v0-p4-construction-real-resources
state: RESERVED_FOR_V0_P4_CLOSURE_NO_ACTIVE_RUNTIME_MUTATION
```

P4 closure не потребляет runtime worker, но lease не переводится автоматически на P5. После P4 acceptance main должен отдельным control update назначить P5 и exact accepted P4 successor base.

## P5 target

P5 делает canonical items реально используемыми equipment/tools.

Минимальная вертикаль:

```text
canonical item
→ server-authoritative equip / unequip
→ replicated equipment state
→ reconnect restores same equipment
→ a real gameplay action requires/uses the equipped tool
```

Предпочтительный первый gameplay binding — mining tool. CH9.6 может быть donor presentation/equipment semantics, но не product base и не Item Graph authority.

## P6 target

P6 — первый стабильный persistent shared-outpost baseline:

```text
join
→ mine
→ inventory / container
→ equip tool
→ build from real resources
→ second client converges
→ reconnect
→ server restart
→ same canonical outpost reconstructed
```

Минимальные acceptance outcomes:

- 5 чистых end-to-end повторов;
- 30-minute two-client soak;
- persistent inventory/equipment/Construction reconstruction;
- zero duplicate canonical truth.

## Post-P6 seamless insertion

После P6 P7 не auto-dispatchится.

Обязательные документы:

- `docs/plans/V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`
- `docs/plans/V0_MULTI_ROUTE_PROJECTION_FABRIC_RU.md`

Main должен записать одно решение:

```text
ACTIVATE_V0_SM1
или
DEFER_V0_SM1_WITH_EXPLICIT_HUMAN_DECISION
```

SM0/MRPF при этом используются как evidence/capability donors. Future V0-SM1 стартует от accepted P6 baseline, а не от historical lab branch.

## NX

NX/H0.2 остаётся самостоятельной HIGH-risk network-authority линией. V0/P продолжает использовать `SERVER_PREDICTED` как базовый network model, пока canonical NX acceptance/control явно не изменит это правило.

Любая реальная потребность P в новом protocol ownership, authority transfer/reconciliation model или Character ownership change fail-closed маршрутизируется в NX. Это конкретная dependency, а не причина блокировать P всей NX веткой целиком.

## ECO

ECO — experimental/research frontier и сейчас **не блокирует V0/P**.

Harness правило:

```text
research status alone != product blocker
```

Research branch становится P blocker только при явной main-registered dependency, обязательном canonical foundation precondition, доказанном ownership/directional-watch intersection или явном потреблении research capability в P Work Order.

Следовательно, ECO может продолжать свои эксперименты независимо и не входит в P4/P5/P6 critical path.

## Fail-closed boundaries for P

Остановить текущий P checkpoint и перепланировать, если требуется:

```text
second Item Graph owner
second Construction truth
second persistence/durability owner
private V0 network authority
new network protocol/authority foundation without NX route
successor runtime dispatch before predecessor checkpoint acceptance
successor branch not based on exact main-declared accepted predecessor lineage
second pre-H0.3 runtime mutation worker
P7 dispatch after P6 without durable seamless activation/defer decision
research branch used as implicit product blocker without a registered dependency
```

Historical branches remain evidence/capability donors unless main-owned control explicitly declares an exact head as the product execution input.
