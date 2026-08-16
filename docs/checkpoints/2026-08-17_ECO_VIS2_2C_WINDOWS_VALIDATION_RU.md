# ECO VIS2.2-C — Windows validation

Дата: 2026-08-17

Статус: **WINDOWS_RUNTIME_VALIDATED_CANDIDATE**

Не merge. Не self-accept. VIS2.2 в целом остаётся открытым.

## Exact lineage

Branch:

`feature/eco-vis2-2-replicated-causal-observatory`

Validated checkpoint HEAD:

`4445338675ab930cee552ac0898a58e38f78b2b5`

VIS2.2-C code-under-test:

`0532c5334cd0a083b4e2dc1a2711f4ba6fd4e380`

VIS2.2-A previously Windows-validated:

`950bcdaa2463f1604865aec8580b418c9eb5c1bc`

## Windows evidence

Exact engine:

`4.7.1.stable.double.custom_build.a13da4feb`

Full `RUN_ECO_VIS2_2C_TESTS.ps1` gate passed on Windows.

Observed inherited/regression evidence:

- VIS2.1-V accepted regression gate: PASS;
- VIS2.2-A replicated causal runner set: PASS (131 assertions);
- VIS2.2-B R2 parser preflight: PASS;
- VIS2.2-B R2 canonical aggregate effect model: PASS (218 assertions);
- VIS2.2-B R2 automated gate: PASS;
- VIS2.2-C parser preflight: PASS;
- VIS2.2-C observatory panel: PASS (42 assertions);
- VIS2.2-C automated gate: PASS.

Strict shutdown gates remained active for ObjectDB, RID/RIDs/RID allocations, resources/cache, StringName, Godot ERROR/SCRIPT ERROR/Parse Error, timeout and PASS-marker enforcement.

No shutdown leak/error diagnostics were observed.

## C invariants validated

VIS2.2-C remains presentation-only. It accepts already-computed bounded VIS2.2-B aggregate data, deep-copies caller input, and selected-replicate changes do not mutate aggregate points or `series_hash`.

This checkpoint authorizes proceeding to VIS2.2-D integrated-lab implementation. It does not constitute merge/global acceptance.