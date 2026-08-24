# V0-P4 — Real Resource Construction — Pre-build Design / Risk / Repair Map

**Date:** 2026-08-16  
**Program:** V0  
**Stage:** P4 — Construction consumes real resources  
**Risk:** HIGH  
**Work Order:** #118  
**Branch:** `feature/v0-p4-construction-real-resources`  
**Stacked base:** `ef3ad5f0afc433802d639171d938e4720b3a46ec` (`repair/v0-p3-visual-interaction-r1`)  
**Canonical main observed at dispatch:** `09714b6f2681e3b5cf3f2f9e28416cf9a7378304`  
**Canonical main registry generation observed at dispatch:** `79`  
**State:** `PREBUILD_ACTIVE / RUNTIME_MUTATION_BLOCKED_UNTIL_V0_CONTROL_ACTIVATION`

## 1. Why this document exists

P4 is the first V0 stage that must create a real causal economy loop:

```text
resource node
  -> P3 authoritative mining
  -> canonical M4 Item Graph / player inventory
  -> server-owned construction affordability/allocation
  -> one atomic construction transaction
  -> Item Graph material debit + Construction stage commit
  -> replication / reconnect convergence
```

The branch is intentionally created now so the investigation, risks and RED contracts are durable Git state. It is **not** evidence that runtime mutation has been authorized by canonical `main`.

## 2. Control-plane stop condition

At branch creation time canonical `main` is still:

```text
09714b6f2681e3b5cf3f2f9e28416cf9a7378304
registry generation 79
```

PR #98 (`control/v0-vertical-slice-critical-path`) is the generation-80 V0 activation candidate and remains outside canonical `main` at this boundary.

The stacked P3.1 base already contains branch-local V0/control artifacts that can look newer than canonical main. They **must not be interpreted as main-owned authorization**.

Therefore this branch may durably contain:

- Design Brief / Risk Map / Repair Map;
- RED-first tests and fixtures;
- source audit evidence;
- proposed implementation boundaries.

It must not modify production/runtime behavior until:

```text
PR #98 (or successor canonical activation) accepted into main
  -> main movement observed
  -> post-main standard Project Control NON_RED
  -> post-main directional Project Control NON_RED for critical hits
  -> exact epoch/base dependency audit
  -> CONTINUE, or REFRESH_REQUIRED and explicit refresh
```

If the canonical activation chooses a different V0 route, this stacked branch is evidence/implementation input, not an authority to bypass that route.

## 3. Explicit exclusions

The following are intentionally excluded from P4 R1:

- PR #117 network repair unless independently accepted and deliberately integrated later;
- new network authority model;
- second Item Graph owner;
- shadow inventory/resource balance;
- client-authoritative affordability or item selection;
- new persistence owner;
- crafting/refining/economy trees;
- tools/equipment progression;
- terrain/matter excavation;
- market systems;
- P5 production loop.

P3.1 independent acceptance is also a separate governance boundary; stacking on its demonstrated Windows head does not self-accept P3.1.

## 4. Current shipped behavior

### 4.1 P3 resource output is already canonical M4 state

P3 mining uses `ResourceMiningService`, and `networked_gameplay_service_p3.gd` injects the service-owned `_canonical_multiplayer_items` instance into mining.

The first V0 resource catalog currently produces:

```text
resource_definition_id = resource/ore
output_definition_id   = item/ore
unit_item_quantity     = 1
```

The trusted server output path writes this ore into the canonical multiplayer Item Graph and into the requesting player's inventory location.

### 4.2 Live MVP Construction still uses fixture material truth

`scripts/construction/mvp/mvp_earth_outpost_authority.gd` currently constructs an `InMemoryConstructionItemGraphAdapter` and preloads fixture parts plus:

```text
item/mvp/earth-outpost/fasteners
  definition = fastener
  quantity = 12
```

The live outpost therefore does not consume P3-mined `item/ore` at all.

This is the core P4 integration gap.

## 5. Canonical truth invariant

P4 MUST preserve exactly one mutable live Item Graph truth:

```text
NetworkedGameplayService._canonical_multiplayer_items
```

The exact same object identity must back:

```text
P3 mining output
P1/P2/P3 inventory and item commands
P4 construction affordability
P4 construction material debit
M3 Item Graph replication
P2/P3 durable recovery
```

Forbidden implementation:

```text
M4 snapshot -> copy into Construction ItemRegistry -> mutate both
```

That creates two authoritative Item Graphs and makes rollback/reconnect ambiguous.

Construction State remains owned by the existing Construction subsystem. P4 is a cross-domain transaction integration, not an ownership transfer.

## 6. Representation mismatch discovered during source audit

The existing `AuthoritativeConstructionItemGraphAdapter` operates on the production Construction item domain:

- `ItemRegistry`;
- `ContainerRegistry`;
- `ItemRelationshipValidator`;
- `ItemMassService`;
- `ItemOperationLedger`;
- M0 transaction bridge;
- `item_instance.v2` / `ConstructionItemProjection`.

Live M4 stores a different canonical wire/runtime representation:

```text
item_id
definition_id
quantity
location
mounted
```

Player inventory ownership is represented by:

```text
location.kind = INVENTORY
location.player_id = <logical player>
location.slot_index = <stable slot>
```

Therefore direct injection of M4 into the existing authoritative Construction adapter is not API-compatible.

### Selected direction

Use the existing Construction transaction-port abstraction as the seam and implement a **bounded live-M4-backed Construction transaction adapter/port** that:

1. references the existing M4 instance rather than copying it;
2. projects only the fields Construction needs;
3. validates all preconditions against current live M4 state;
4. stages candidate M4 + Construction mutations before commit;
5. commits or restores both sides as one operation boundary;
6. reuses the existing Construction operation/replay contract rather than creating a second command ledger;
7. never exposes a client write path for trusted material allocation.

If implementing this requires changing global Item Graph ownership or introducing a new world transaction foundation, STOP and escalate to CRITICAL instead of silently expanding P4.

## 7. Startup/composition ordering defect

Current MVP startup order is approximately:

```text
create M3DedicatedServerRuntime
create fixture Construction gateway
bind ConstructionBridge
M3DedicatedServerRuntime.setup()
  -> create NetworkedGameplayService
  -> create canonical M4 Item Graph
```

`set_construction_bridge()` currently requires binding before M3 runtime setup, while the live M4 instance only exists during/after setup.

P4 therefore needs a bounded composition seam such as a construction factory/service-ready binder that executes after canonical gameplay/M4 creation but before clients are accepted.

Acceptance invariant:

```text
object identity used by ResourceMiningService
== object identity used by P4 Construction material transaction port
```

Do not solve ordering by creating a second Item Graph earlier.

## 8. Server-side material allocation

The client may submit construction intent/stage advancement. It must not nominate authoritative inventory item IDs.

Trusted identity source:

```text
M3 peer/session validation
  -> _peer_to_player[peer_id]
  -> logical_player_id
```

P4 allocator then reads only that player's current canonical inventory.

### First P4 recipe

```text
required definition: item/ore
quantity: bounded fixed recipe quantity
```

### Deterministic selection

Eligible stacks MUST be sorted by:

1. canonical inventory `slot_index` ascending;
2. canonical `item_id` ascending as the tie breaker.

Then allocate from stacks in that order until the recipe quantity is covered.

Consequences:

- Dictionary iteration order is never authoritative;
- multiple stacks are supported;
- another player's ore is never eligible;
- open external containers are not implicitly spendable in R1;
- missing/ambiguous ownership fails closed;
- insufficient quantity rejects before mutation.

## 9. Exact-consume defect — three-layer repair required

Source audit found that exact stack exhaustion is currently impossible in the Construction build path.

### Layer A — BuildPlan validation

`construction_build_plan.gd` currently rejects:

```text
material_totals >= source.quantity
```

with:

```text
BUILD_PLAN_MATERIAL_WOULD_EXHAUST_STACK
```

For P4 this comparison is wrong.

Required semantics:

```text
material_totals > source.quantity  -> reject shortfall
material_totals == source.quantity -> valid exact exhaustion
material_totals < source.quantity  -> valid partial consumption
```

### Layer B — Stage transaction planner

`construction_stage_transaction_planner.gd` currently always emits `OP_UPDATE` for material consumption and calculates:

```text
after.quantity = before.quantity - allocation.quantity
```

Exact exhaustion therefore creates a zero-quantity projection, while `ConstructionItemProjection.validate()` requires quantity >= 1.

Required semantics:

```text
remaining > 0 -> OP_UPDATE with revision +1
remaining == 0 -> OP_DELETE with empty after_projection
remaining < 0 -> fail before transaction creation
```

### Layer C — ItemMutation validation

`construction_item_mutation.gd` supports `OP_DELETE`, but currently accepts deletion only for `DESTROY_CONSTRUCT_ROOT` and `CONSUME_FABRICATION_INPUT`.

It does **not** accept:

```text
OP_DELETE + PURPOSE_CONSUME_MATERIAL
```

P4 must add a narrowly scoped valid exact-consumption delete case. It must not broaden arbitrary deletion rights.

For a material delete, the before projection must be a valid transferable consumable source and the after projection must remain empty.

## 10. Exact-once ordering risk

Existing Construction process/adapter already contains operation-level replay machinery, but P4 introduces server-side allocation before planning.

A duplicate accepted operation MUST NOT re-run allocation against a changed inventory and produce a different plan.

Required logical order:

```text
trusted player/session validation
  -> operation id + command fingerprint replay/conflict lookup
  -> if accepted before: return same accepted outcome, no allocation, no debit
  -> if same operation id / different payload: conflict
  -> otherwise read current inventory
  -> deterministic allocation
  -> freeze transaction inputs
  -> authoritative atomic commit
  -> persist accepted outcome
```

This ordering is a required test target, not an implementation detail.

## 11. Atomic rollback risk

P4 success spans two canonical domains:

```text
M4 Item Graph
Construction State
```

Required failure invariant:

```text
before transaction == after failed transaction
```

for:

- ore quantity/existence;
- inventory membership/slot identity;
- Item Graph revision/tick/checksum according to the chosen transaction contract;
- Construction snapshot/revision;
- operation terminal state;
- M0/contribution state if participating in this P4 composition.

There must never be:

```text
ore consumed + stage unchanged
```

or:

```text
stage advanced + ore unchanged
```

If the current M4 API cannot provide the required prepare/commit/restore semantics without changing global ownership, STOP and escalate rather than implementing two sequential commands.

## 12. Publication ordering

Current M3 Construction command publication broadcasts a Construction event, while Item Graph commands have their own delta/full-snapshot fallback path.

P4 must publish only after successful compound commit:

```text
successful P4 transaction
  -> Item Graph delta (or full snapshot fallback)
  -> Construction event/snapshot
  -> gameplay/convergence report
```

A replication-delta build failure after authoritative commit must not convert the command into a rejection. Use full authoritative resync fallback, matching existing M3 Item Graph doctrine.

## 13. Persistence/reconnect boundary

P4 must not add a persistence store.

The acceptance requirement is that existing durable owners serialize the already-committed canonical state and reconnect reconstructs:

- post-debit Item Graph;
- player inventory membership;
- Construction stage/snapshot;
- replay/idempotency outcome.

P3.1 reconnect repair is a prerequisite input but is not equivalent to full P4 reconnect acceptance.

## 14. RED-first test matrix

### P4.1 exact-consume contracts

- BuildPlan accepts exact material exhaustion;
- shortfall still rejects;
- partial consumption produces UPDATE;
- exact consumption produces DELETE;
- `OP_DELETE + PURPOSE_CONSUME_MATERIAL` validates only for the bounded material case;
- container membership is removed for exact deletion.

### P4.2 allocator

- one stack sufficient;
- deterministic multi-stack allocation;
- exact boundary;
- insufficient total;
- foreign-player stacks excluded;
- stable slot order then item-id tie break;
- missing player/inventory fails closed;
- client-supplied item IDs cannot override allocation.

### P4.3 live transaction

- same M4 object instance is used by mining and construction;
- P3-produced `item/ore` is accepted as construction input;
- partial debit;
- exact debit/delete;
- stale precondition / TOCTOU rejects without partial mutation;
- fault after Item Graph prepare/apply rolls back Construction and Item Graph;
- fault after Construction apply rolls back both;
- duplicate accepted command consumes once;
- same operation ID/different payload conflicts.

### P4.4 M3/reconnect

- A mines real ore;
- B observes Item Graph/resource state;
- A builds;
- ore consumed exactly once;
- Construction advances exactly once;
- B observes both results;
- duplicate command has no second effects;
- disconnect/reconnect reconstructs exact Item Graph + Construction state;
- no reconnect-triggered economy mutation.

## 15. Expected implementation surfaces after activation

Likely bounded runtime surfaces:

```text
scripts/construction/build/construction_build_plan.gd
scripts/construction/build/construction_stage_transaction_planner.gd
scripts/construction/item_graph/construction_item_mutation.gd
scripts/construction/mvp/mvp_earth_outpost_authority.gd
scripts/runtime/networked_gameplay/m4/... P4 transaction port/adapter
scripts/runtime/networked_gameplay/p3/networked_gameplay_service_p3.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime*.gd
scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd
scripts/app/simulator_app.gd (only if composition factory cannot live lower)
```

This list is a watched design surface, not permission to edit all files.

Prefer a new bounded adapter/factory over widening mature canonical owners.

## 16. Stop/escalation conditions

STOP P4 and require Director/Human architecture decision if any implementation requires:

- a second mutable Item Graph;
- ownership transfer from M4;
- new global transaction foundation;
- new persistence authority;
- network protocol/authority redesign;
- inclusion of PR #117 as an implicit dependency;
- material ontology expansion beyond the bounded `item/ore` recipe;
- client authority over inventory source selection;
- production mutation while canonical main activation remains unresolved.

## 17. P4 R1 completion statement

P4 R1 is complete only when the following statement is proven on one exact reviewed/tested head:

> Руда, реально добытая игроком через P3 и находящаяся в его authoritative M4 inventory, используется сервером для продвижения реального Construction stage. Успех списывает требуемый `item/ore` и продвигает stage атомарно и ровно один раз; exact exhaustion удаляет стек; insufficient resources, ownership failure, duplicate/conflicting operation или injected transaction failure не оставляют частичного состояния. Второй клиент и reconnect сходятся к тому же Item Graph + Construction состоянию. Второго authoritative Item Graph или resource balance не существует.

## 18. Immediate next actions

While runtime mutation remains blocked:

1. land RED behavioral contracts for exact exhaustion and mutation semantics;
2. land allocator contract tests against a test seam only;
3. keep all production/runtime files unchanged;
4. record exact branch heads in Work Order #118.

After canonical activation:

1. re-resolve exact main/epoch and decide CONTINUE vs REFRESH_REQUIRED;
2. run Project Control before first runtime mutation;
3. implement P4.1 exact-consume repair;
4. implement server allocator;
5. implement live-M4 transaction port and composition seam;
6. add M3 publication/reconnect coverage;
7. run focused + inherited P1/P2/P3 regressions + Project Control;
8. hand exact head to independent Reviewer and Verifier;
9. do not self-accept or merge.
