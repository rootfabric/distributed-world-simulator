# V0-P4 RED contract — execution status

The first P4 behavioral contract is committed at:

`tests/construction/test_v0_p4_real_resource_exact_consume_contract.gd`

Focused runner:

`RUN_V0_P4_EXACT_CONSUME_CONTRACT.ps1`

## Status

**NOT EXECUTED as runtime evidence in this implementation session.**

The branch is still under the canonical runtime-mutation stop condition documented in the P4 Risk Map. No PASS/FAIL count is claimed here.

The expected current RED behavior is derived directly from the existing production contracts:

- exact material exhaustion is rejected by `ConstructionBuildPlan.validate()` because it currently rejects `material_totals >= source.quantity`;
- if that guard is relaxed alone, the stage planner still produces an UPDATE to quantity zero;
- `ConstructionItemProjection` rejects quantity zero;
- an attempted DELETE using `PURPOSE_CONSUME_MATERIAL` is currently rejected by `ConstructionItemMutation.validate()`.

The Windows operator or later exact-head verifier can execute:

```powershell
.\RUN_V0_P4_EXACT_CONSUME_CONTRACT.ps1 -ExpectedHead <exact-head>
```

Before the P4.1 production repair, a RED result is expected. After the bounded P4.1 repair, this same runner must become GREEN before allocator/live-M4 integration proceeds.

This file prevents static source reasoning from being misreported later as executed runtime evidence.
