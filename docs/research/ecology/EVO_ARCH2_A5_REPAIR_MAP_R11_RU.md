# EVO ARCH2 A5 — Repair Map R11

Scope: bounded continuation of A5 only, after fresh review of subject `2c4c8a7a87428d245cca3ea2e51eef6bdf59b108`.

## RM-A5-21 — seal parent-transfer construction

Fresh P1: public `ResourceLifecycleRuntimeV1.individual()` accepted caller-selected `origin_kind = PARENT_TRANSFER`, allowing arbitrary endowed child state without propagule or paid-parent witness.

Repair:
- public `individual()` is founder-only and fails closed for every non-founder origin;
- `materialize_propagule()` remains the only A5 runtime path that creates a `PARENT_TRANSFER` state and only executes after `validate_propagule(..., paid_parent_state)` succeeds;
- no callable underscore helper is used as a pseudo-private bypass.

Negative control: direct `individual(..., PARENT_TRANSFER)` with maximal valid stock must return empty.
Positive control: real paid reproduction + exact parent witness must still materialize an exact-endowment child.

Executable oracle: `validation/ecology/evo_arch2_a5/rm_a5_21_parent_transfer_constructor_seal.gd`.

## RM-A5-22 — maintenance history causality

Fresh P2: RM-A5-19 bounded persisted maintenance only by reproduction event count. That is insufficient: a long-lived alive state proves repeated maintenance payments are necessary to avoid `starvation_limit_ticks`, and A2 `development.grant_seq` independently proves ticks on which maintenance had to be paid before development could advance.

Repair uses a conservative lower bound on the number of paid maintenance ticks:

`required_paid_ticks = max(reproduction_event_count, ceil((age_ticks - starvation_ticks) / starvation_limit_ticks), development.grant_seq)`

The maintenance ledger must contain at least root-module water/energy maintenance for `required_paid_ticks`. This does not claim the full historical module-count integral; it only rejects states that are impossible even under the cheapest causally valid history.

Negative controls:
- long-lived reproduced state with maintenance refunded down to one payment per reproduction event;
- development-rich state with maintenance refunded below `development.grant_seq` proof.

Positive controls are produced by the real A5 runtime and must remain serializable/valid.

Executable oracle: `validation/ecology/evo_arch2_a5/rm_a5_22_maintenance_history_causality.gd`.

## Acceptance gate

Freeze final implementation HEAD/TREE, run exact double Godot cold import, A5 core + reviewer repairs + RM-A5-11..22 twice with byte-identical logs, A4/A0-A3/VIS5 regressions, then request a new independent review of that exact subject. No A5 acceptance is allowed before both verifier PASS and fresh review with zero blocking findings.