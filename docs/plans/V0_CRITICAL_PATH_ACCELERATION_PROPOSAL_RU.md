# V0 Critical Path Acceleration — P0→P4 Product-Lineage Refresh

**Status:** `GENERATION-80 CONTROL REFRESH CANDIDATE / NOT CANONICAL UNTIL MAIN ACCEPTANCE`  
**Repository:** `rootfabric/distributed-world-simulator`  
**PR:** `#98`  
**Original control base:** `main @ 09714b6f2681e3b5cf3f2f9e28416cf9a7378304`  
**Architecture:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`

## 1. Почему исходный вариант PR #98 устарел

Исходный generation-80 proposal решал правильную проблему: V0 не должен ждать H0.3 и NX.C1, если один bounded product worker может использовать существующий `SERVER_PREDICTED` runtime.

После его создания реальный product train ушёл вперёд:

```text
P0 playable frontier
→ P1 world items / containers
→ P2 reconnectable shared state
→ P3 resource mining
→ P3.1 visual interaction repair
→ P4 preparation
```

Поэтому два исходных предположения стали вредными:

1. новый V0 runtime Work Order обязан начинаться byte-for-byte от `exact current main`;
2. после первого outpost checkpoint следующим продуктовым направлением должен быть Ship-0.

Первое заставляет выбрасывать уже проверенную композицию P0-P3. Второе уводит critical path от замыкания базового gameplay loop.

## 2. Что сохраняется из старого proposal

Следующие правила остаются правильными и обязательными:

```text
SERVER_PREDICTED remains valid V0 baseline
H0.2 / NX.C1 is not a blanket V0 prerequisite
pre-H0.3 total runtime mutation workers <= 1
verification/review-only work may coexist with one mutation worker
V0 cannot invent private network/authority foundations
network foundation change fails closed to NX
```

Refresh не ослабляет NX acceptance и не разрешает несколько runtime workers.

## 3. Новая модель: main owns control, product lineage owns continuation input

Нужно различать две вещи:

```text
CONTROL / PROJECT EPOCH
  anchored to exact canonical main

RUNTIME PRODUCT EXECUTION BASE
  exact V0 lineage head declared by main-owned control
```

`MAIN DECLARES PROJECT STATE` не означает `EVERY PRODUCT BRANCH MUST RESTART FROM MAIN BYTES`.

Main может объявить точную проверенную product lineage как execution input, сохраняя за собой:

- право разрешить или запретить продолжение;
- architecture ownership;
- checkpoint/risk/review rules;
- mutation-worker ceiling;
- human merge gates.

## 4. Текущий main-declared P4 execution base

Для generation-80 refresh exact product input фиксируется как:

```text
branch:
repair/v0-p3-visual-interaction-r1

sha:
ef3ad5f0afc433802d639171d938e4720b3a46ec
```

Почему не `main`:

- current main не содержит текущую P0-P3 product composition;
- P1/P2/P3 уже проходили реальный Windows/Godot runtime train;
- mining P3.1 реально проверен оператором;
- P4 preparation уже построена именно на этом exact head.

Почему не PR #117 head:

```text
11819f6dd1ea3728382a04737d30a5300de622f7
```

#117 является отдельным HIGH-risk replica repair и пока не должен silently enter P4 before independent acceptance. Он остаётся отдельным review/verification gate перед финальной replication/soak confidence.

Execution-base declaration **не является P3 acceptance**.

## 5. Фактическое состояние P0-P4

### P0

Validated playable frontier already proves:

- procedural Earth;
- dedicated server;
- clients A/B;
- playable movement;
- canonical inventory composition;
- authoritative Construction presentation/replication.

### P1

PR #103 current head:

```text
f7ab0a8b91394724b66e3f4ee387de3441a676ca
```

World items, pickup/drop, external containers and modern canonical inventory composition are present. Fresh P1 review is PASS.

### P2

PR #109 exact candidate:

```text
92e3e197e11156d6c36a58a3b4a4f447397c99d7
```

Status at refresh:

```text
Windows exact-head GREEN
Reviewer PASS
Verifier PASS
Director verdict pending
```

### P3

Base mining candidate:

```text
f27a60279c8ad61d47ebe3fad81b6898679c660f
```

P3.1 interaction repair:

```text
ef3ad5f0afc433802d639171d938e4720b3a46ec
```

Operator evidence demonstrated real mining and second-client depletion visibility.

### P4

Current branch:

```text
feature/v0-p4-construction-real-resources
```

Refresh input head:

```text
c20310cf804374ab515fd7a363b6471c2b933ac0
```

Already durable:

- HIGH-risk Work Order #118;
- source/risk Repair Map;
- exact-consume RED contract;
- exact P4.1 three-file patch prepared;
- no production/runtime mutation yet because generation-80 activation is not canonical.

## 6. Current product checkpoint

Generation-80 refresh activates:

```text
V0_P4_REAL_RESOURCE_CONSTRUCTION
```

Target loop:

```text
resource.mine
→ canonical item/ore
→ player inventory
→ build intent
→ deterministic server allocation
→ atomic resource debit + Construction commit
→ A/B publication
→ reconnect convergence
```

## 7. P4 technical sequence

### P4.1 — exact stack consumption

Repair exactly three existing Construction surfaces:

```text
construction_build_plan.gd
construction_stage_transaction_planner.gd
construction_item_mutation.gd
```

Required behavior:

```text
requested > available  -> reject
requested < available  -> UPDATE remaining quantity
requested == available -> DELETE exhausted stack
```

Existing adapters already support `DELETE`; no adapter/M0 redesign is required for P4.1.

### P4.2 — deterministic server allocator

```text
logical_player_id resolved server-side
eligible definition_id == item/ore
requesting player's canonical inventory only
stable order = (slot_index, item_id)
multi-stack allocation supported
client item IDs are never trusted
```

### P4.3 — live M4 Construction transaction port

Construction must mutate the same canonical M4 Item Graph that P3 mining writes.

Forbidden:

```text
M4 -> mutable copied ItemRegistry
second Item Graph
shadow material balance
```

### P4.4 — composition ordering

Construction gateway must receive the already-created canonical M4 owner through a bounded factory/composition repair rather than late unsafe binding or duplicate state.

### P4.5 — publication

Successful atomic outcome publishes:

```text
Item Graph delta/full fallback
+
Construction event/snapshot
```

Failure publishes neither success mutation.

### P4.6+ hardening

- duplicate exact-once;
- same operation ID / different payload conflict;
- shortfall mutation-free;
- ownership isolation;
- source changed/removed before commit;
- fault-injection rollback;
- revision/tick purity;
- A/B replication;
- reconnect convergence.

## 8. Acceptance debt is not hidden

Current inherited debt:

```text
P2 Director verdict pending
P3 aggregate Reviewer / Verifier / Director pending
PR #117 independent HIGH-risk routing pending
```

Generation-80 refresh applies this policy:

```text
bounded P4 implementation
  MAY continue after activation + post-main PC0 + Director dispatch

P4 checkpoint acceptance / stable V0 baseline
  MUST wait for applicable inherited acceptance debt
```

This is deliberate. Otherwise governance lag would repeatedly stop implementation even when exact product behavior is already demonstrated; conversely, simply declaring the debt irrelevant would make review meaningless.

## 9. Worker concurrency

Before H0.3:

```text
runtime mutation workers <= 1
```

Recommended current slot owner:

```text
P4
```

May coexist:

```text
P2/P3/#117/NX/SM0 review-only or verification-only work
```

Must serialize:

```text
P4 mutation + NX non-trivial mutation
P4 mutation + SM0 non-trivial mutation
```

## 10. Product order after P4

The product train is now:

```text
P4 real-resource Construction
→ P5 equipment/tools
→ P6 persistent shared outpost
→ P7 bounded terrain mutation
→ P8 first mobile construct / ship
```

P6 means:

```text
join
→ mine
→ move items through inventory/container
→ build outpost
→ disconnect/reconnect
→ continue same world
→ 5 clean E2E repeats
→ 30-minute two-client soak
```

This is the stable V0 playable baseline target.

## 11. Что не должно блокировать P4/P6

Unless a concrete scenario proves otherwise:

```text
H0.3 multi-worker scheduler
NX.C1 OWNER_AUTHORITATIVE_VALIDATED acceptance
SM0 production handoff integration
terrain deformation
full Matter stack
ECO production
large structural simulation
ship flight / orbital transition
advanced economy/crafting
```

## 12. Что происходит после merge generation-80 refresh

PR #98 merge itself does not immediately authorize blind mutation on an old branch.

Required sequence:

```text
merge generation-80 control to main
        ↓
fetch exact new main
        ↓
post-main standard PC0
        +
post-main directional PC0
        ↓
fresh P4 epoch/base dependency audit
        ↓
CONTINUE existing P4 branch
or
REFRESH_REQUIRED bounded capability transfer
        ↓
Director dispatch
        ↓
P4.1 RED -> GREEN
```

Thus the refresh removes the stale instruction without removing the safety check that main movement can invalidate dependencies.

## 13. Final rule

```text
MAIN OWNS AUTHORIZATION
EXACT PRODUCT LINEAGE MAY OWN CONTINUATION INPUT
ACCEPTANCE DEBT REMAINS VISIBLE
ONE MUTATION WORKER UNTIL H0.3
P4/P6 BEFORE TERRAIN OR SHIPS
NO DUPLICATE TRUTH
```
