# V0-P4.1 — exact-consume production patch prepared

Дата: 2026-08-16

## Статус

```text
IMPLEMENTATION_READY
PRODUCTION_PATCH_NOT_APPLIED
RUNTIME_MUTATION_BLOCKED_BY_MAIN_CONTROL
```

Это durable implementation package для первого P4 production repair. Он не является PASS/acceptance и не изменяет production runtime.

## Exact execution facts

Перед подготовкой patch:

```text
P4 branch:
feature/v0-p4-construction-real-resources

exact branch HEAD:
f439a835d1c4472e36afaff7c9441e5120ef6b8e

stacked P3.1 base:
ef3ad5f0afc433802d639171d938e4720b3a46ec

canonical main:
09714b6f2681e3b5cf3f2f9e28416cf9a7378304
registry generation: 79

V0 activation PR #98:
OPEN / NOT CANONICAL
```

Main-owned `project-goals.v1.json` and `checkpoint-catalog.v1.json` still do not declare V0/P4 as an eligible runtime checkpoint. Root `AGENTS.md` and Project Control therefore block production/runtime mutation until canonical V0 activation, post-activation Project Control and fresh epoch/base audit.

## Root cause confirmed on exact P4 HEAD

P4.1 exact-stack consumption is blocked in three layers.

### 1. BuildPlan rejects equality

Current:

```gdscript
if int(material_totals[item_id]) >= int(source["quantity"]):
    return _failure("BUILD_PLAN_MATERIAL_WOULD_EXHAUST_STACK")
```

Correct bounded semantics:

```gdscript
if int(material_totals[item_id]) > int(source["quantity"]):
    return _failure("BUILD_PLAN_MATERIAL_WOULD_EXHAUST_STACK")
```

Equality means exact exhaustion and must be valid. Existing error code is intentionally retained for compatibility; only its rejection boundary changes.

### 2. Stage planner always emits UPDATE

Current planner computes `after.quantity = before.quantity - allocation.quantity` and always emits `OP_UPDATE`.

For exact exhaustion this creates `quantity == 0`, which cannot be a valid `ConstructionItemProjection`.

Correct semantics:

```text
remaining > 0  -> UPDATE with revision + 1
remaining == 0 -> DELETE with empty after_projection
remaining < 0  -> impossible after valid BuildPlan; fail closed if encountered
```

### 3. ItemMutation rejects DELETE + CONSUME_MATERIAL

`ConstructionItemMutation.validate()` currently permits DELETE only for:

- `DESTROY_CONSTRUCT_ROOT`;
- `CONSUME_FABRICATION_INPUT`.

P4 requires `DELETE + CONSUME_MATERIAL` as the canonical representation of an exhausted material stack.

## Minimal production patch

Only these production files are required for P4.1:

```text
scripts/construction/build/construction_build_plan.gd
scripts/construction/build/construction_stage_transaction_planner.gd
scripts/construction/item_graph/construction_item_mutation.gd
```

No adapter, persistence, M0, M3, network or M4 file belongs in P4.1.

### Patch A — BuildPlan exact exhaustion

```diff
--- a/scripts/construction/build/construction_build_plan.gd
+++ b/scripts/construction/build/construction_build_plan.gd
@@
-			if int(material_totals[item_id]) >= int(source["quantity"]):
+			if int(material_totals[item_id]) > int(source["quantity"]):
 				return _failure("BUILD_PLAN_MATERIAL_WOULD_EXHAUST_STACK")
```

### Patch B — planner UPDATE/DELETE split

```diff
--- a/scripts/construction/build/construction_stage_transaction_planner.gd
+++ b/scripts/construction/build/construction_stage_transaction_planner.gd
@@
 		var before: Dictionary = initial.duplicate(true)
 		before["quantity"] = int(initial["quantity"]) - consumed_before
 		before["revision"] = int(initial["revision"]) + previous_mutations
-		var after: Dictionary = before.duplicate(true)
-		after["quantity"] = int(before["quantity"]) - int(allocation["quantity"])
-		after["revision"] = int(before["revision"]) + 1
-		mutations.append(ItemMutationScript.create(
-			ItemMutationScript.OP_UPDATE,
-			ItemMutationScript.PURPOSE_CONSUME_MATERIAL,
-			item_id,
-			before,
-			after
-		))
+		var remaining: int = int(before["quantity"]) - int(allocation["quantity"])
+		if remaining < 0:
+			return _failure("CONSTRUCTION_BUILD_STAGE_MATERIAL_SHORTFALL")
+		if remaining == 0:
+			mutations.append(ItemMutationScript.create(
+				ItemMutationScript.OP_DELETE,
+				ItemMutationScript.PURPOSE_CONSUME_MATERIAL,
+				item_id,
+				before,
+				{}
+			))
+		else:
+			var after: Dictionary = before.duplicate(true)
+			after["quantity"] = remaining
+			after["revision"] = int(before["revision"]) + 1
+			mutations.append(ItemMutationScript.create(
+				ItemMutationScript.OP_UPDATE,
+				ItemMutationScript.PURPOSE_CONSUME_MATERIAL,
+				item_id,
+				before,
+				after
+			))
```

The defensive `remaining < 0` guard is not expected after `BuildPlan.validate()` but prevents a future planner caller from manufacturing a negative quantity if validation boundaries drift.

### Patch C — allow material-consume DELETE

```diff
--- a/scripts/construction/item_graph/construction_item_mutation.gd
+++ b/scripts/construction/item_graph/construction_item_mutation.gd
@@
 			if purpose == PURPOSE_DESTROY_ROOT:
 				if not _is_construction_root(before):
 					return _failure("INVALID_DELETE_ITEM_MUTATION_PURPOSE")
+			elif purpose == PURPOSE_CONSUME_MATERIAL:
+				pass
 			elif purpose == PURPOSE_CONSUME_FABRICATION_INPUT:
 				if String(before["relation"].get("kind", "")) != ProjectionScript.CONTAINER:
 					return _failure("FABRICATION_INPUT_NOT_RESERVED")
```

The validator intentionally does not add a new location restriction here. Transferability is already a BuildPlan invariant, and partial `CONSUME_MATERIAL` UPDATE has the same generic mutation-level semantics. Adding a DELETE-only restriction would make partial and exact consumption inconsistent.

## Sibling execution audit

No additional runtime change is required for DELETE execution.

### In-memory adapter

`in_memory_construction_item_graph_adapter.gd::_apply_item_mutation()` already does:

```gdscript
ItemMutationScript.OP_DELETE:
    target.erase(item_id)
```

### Authoritative adapter

`authoritative_construction_item_graph_adapter.gd` candidate application already does:

```gdscript
ItemMutationScript.OP_DELETE:
    item_rows.erase(item_id)
```

The authoritative adapter then constructs the post-item-graph state and passes the whole before/after aggregate state to the existing M0 translator. No new M0 item-delete operation is required for P4.1.

### Transaction-plan validator

`construction_item_transaction_plan.gd` delegates each mutation to `ConstructionItemMutation.validate()` and does not impose an UPDATE-only rule. Once Patch C is applied, the exact-consume DELETE remains valid at transaction-plan level.

## Existing RED contract

The already committed focused contract covers:

```text
partial consume -> UPDATE, remaining quantity 1
exact consume   -> BuildPlan valid + DELETE + empty after projection
DELETE + CONSUME_MATERIAL -> mutation valid
```

Paths:

```text
tests/construction/test_v0_p4_real_resource_exact_consume_contract.gd
RUN_V0_P4_EXACT_CONSUME_CONTRACT.ps1
```

## Validation status

A clean exact-head runtime execution was attempted in the current tool environment, but the sandbox cannot resolve GitHub for `git clone`; therefore no fabricated RED/PASS count is recorded.

Status remains:

```text
FOCUSED_RUNTIME_RESULT = INSUFFICIENT_EVIDENCE
```

After canonical activation, the required sequence is:

```text
1. fresh main/epoch audit
2. execute existing RED contract on exact pre-fix head
3. apply exactly Patches A-C
4. execute same focused contract -> GREEN
5. run existing C3 Construction regression
6. run broader Construction contract/integration gates appropriate to touched common files
7. post-build critique + Evidence Map
8. independent HIGH-risk Reviewer + Verifier
```

## Stop conditions

STOP_AND_REPLAN if P4.1 requires any of:

```text
new Item Graph owner
adapter redesign
M0 transaction redesign
persistence mutation
network protocol mutation
M4 ownership change
client-provided authoritative material allocation
```

Those are not necessary for the exact-consume defect proven here.
