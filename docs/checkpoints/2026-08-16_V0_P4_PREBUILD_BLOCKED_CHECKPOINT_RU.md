# V0-P4 — PREBUILD BLOCKED CHECKPOINT

**Branch:** `feature/v0-p4-construction-real-resources`  
**Exact stacked base:** `ef3ad5f0afc433802d639171d938e4720b3a46ec`  
**Work Order:** #118  
**Risk:** HIGH  
**State:** `PREBUILD_ACTIVE / RUNTIME_MUTATION_BLOCKED`

## Durable progress

The P4 development train has started and now has durable Git state for:

- the corrected pre-build Design/Risk/Repair Map;
- the canonical single-M4 truth invariant;
- the discovered live Construction fixture-material gap;
- the M4 vs Construction representation mismatch;
- the startup/composition-order dependency;
- the deterministic server-side allocation policy;
- exact-once ordering requirements;
- atomic rollback and publication requirements;
- a RED-first exact-consume behavioral contract;
- a focused exact-head Windows Godot 4.7.1 double runner.

## Current RED defect set

Exact consumption is blocked by three independent current-code constraints:

1. `ConstructionBuildPlan.validate()` rejects `material_totals >= source.quantity`; equality must be legal.
2. `ConstructionStageTransactionPlanner` always emits UPDATE and therefore attempts `quantity = 0` on exact exhaustion.
3. `ConstructionItemMutation.validate()` does not currently admit `OP_DELETE + PURPOSE_CONSUME_MATERIAL`.

All three must be repaired together after runtime activation. A one-layer symptom patch is not sufficient.

## Runtime stop condition

No production/runtime files are intentionally modified at this checkpoint.

At checkpoint creation, canonical `main` is still generation 79 at:

`09714b6f2681e3b5cf3f2f9e28416cf9a7378304`

The generation-80 V0 activation candidate remains outside canonical main. Branch-local newer control artifacts inherited from the P3 stack do not authorize runtime mutation.

Before first production mutation:

```text
canonical V0 activation merged to main
-> observe exact new main
-> standard Project Control NON_RED
-> directional Project Control NON_RED for critical hits
-> exact epoch/base audit
-> CONTINUE or explicit REFRESH_REQUIRED handling
```

## Excluded boundary

PR #117 remains intentionally excluded. P4 must not silently absorb that independent HIGH-risk network repair.

## Next allowed prebuild work

While blocked, tests/fixtures may further specify:

- deterministic server allocation;
- ownership isolation;
- duplicate/conflicting operation behavior;
- rollback expectations;
- reconnect convergence expectations.

The next production implementation step after activation is **P4.1 exact-consume repair**, followed by allocator and live-M4 transaction composition.

This checkpoint is not P4 acceptance, not a merge authorization, and not a claim that canonical runtime dispatch has occurred.
