# FABRIC HOLDOUT-R4 G2 — Repair R4 / COMPLEX2 hot path

## Subject / trigger

Parent product subject:

```text
HEAD = 4ef109b5ae4727605b469dc3600d4337bf8e8642
TREE = 5a9450162e261459d6533fd368c36b2b515d91eb
```

Exact self-hosted `FABRIC COMPLEX2-PERF Scaling Linux Double` on that subject fails the unchanged 12 s case budget at the first 500-part case:

```text
run = 34729552213
job = 103649694056
part_count = 500
total_us = 15476006
budget_us = 12000000
error = COMPLEX2PERF_CASE_BUDGET_EXCEEDED
```

`B0.6-CLOSE` is therefore blocked by the nested PERF gate. The budget itself is not authorized to change.

## Hot-path diagnosis

The scale case spends most of its fixed-cost transient work in `complex2_settle_rebake_reimpact_v1.gd`.
For every settle/reimpact timestep it currently calls both:

```text
Coupled.compiled_step(...)
Coupled.full_reference_step(...)
```

The physical assembly is immutable during those loops, but both public step functions re-run full assembly validation on every timestep. In addition, `full_reference_step()` rebuilds the same time-invariant reference mass/stiffness/damping matrices from unchanged couplings on every timestep.

This is redundant validation/compilation work, not required physical work. State/range/force/timestep guards in `_midpoint_step()` already remain timestep-local.

## Bounded optimization plan

Allowed product scope:

1. `scripts/research/fabric_bake0/complex2_settle_rebake_reimpact_v1.gd`
   - validate immutable coupled assembly once per lifecycle phase;
   - build an independent reference matrix set once per phase from the canonical couplings;
   - reuse the already-compiled assembly matrices for the compiled evaluator;
   - reuse the independently rebuilt reference matrices for the full-reference evaluator;
   - continue to run the same midpoint equations and state/force/range guards every timestep.
2. This Repair Map.

No physics equation, force schedule, timestep, settle criterion, ringdown length, part count, expected hash, tolerance, or performance budget may change.

## Forbidden scope

Do not change:

- `CASE_BUDGET_US` / `LOCAL_REBAKE_BUDGET_US`;
- `MAX_SETTLE_STEPS`, impact/ringdown counts, `DT`, forces, energy/speed thresholds;
- coupled mass/stiffness/damping/coupling constants;
- G2/R3/R2 event/replay semantics;
- frozen G1 evidence;
- canonical legacy serialization;
- acceptance policy to waive the failing gate.

## Correctness invariant

The reference path remains independent of the compiled matrices: reference matrices are freshly reconstructed from `assembly["couplings"]` before the loop. They are cached only because the system matrices are time-invariant for the phase.

Every timestep still executes `_midpoint_step()`, which validates delta, force vector/range and state/refinement bounds before and after integration.

## Acceptance

Repair R4 is implementation-complete only if the final exact product HEAD satisfies:

1. `FABRIC COMPLEX2-PERF Scaling Acceptance: PASS` for 500/1000/2000 with the unchanged 12,000,000 us budget;
2. `FABRIC B0.6-CLOSE Linux Double = PASS`;
3. `FABRIC COMPLEX2-E Settle Rebake Re-impact Linux Double = PASS`;
4. `FABRIC COMPLEX2-C Coupled Motion Linux Double = PASS`;
5. exact G2/R3/R2/R1 runner remains PASS;
6. no threshold/golden/physics weakening;
7. any fresh review/evidence tied to `4ef109b5...` is stale after this mutation and must be regenerated on the final HEAD.

Production freeze, unseen holdout, R4 acceptance and SCALE-R5 remain locked until fresh Reviewer + Verifier + Director closure.
