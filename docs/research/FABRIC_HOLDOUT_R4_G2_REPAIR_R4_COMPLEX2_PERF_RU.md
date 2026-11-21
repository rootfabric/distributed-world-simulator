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

### Stage A — COMPLEX2-E immutable coupled context

The scale case spends fixed-cost transient work in `complex2_settle_rebake_reimpact_v1.gd`. For every settle/reimpact timestep it called both:

```text
Coupled.compiled_step(...)
Coupled.full_reference_step(...)
```

The physical assembly is immutable during those loops, but both public step functions re-ran full assembly validation every timestep. In addition, `full_reference_step()` rebuilt the same time-invariant reference mass/stiffness/damping matrices from unchanged couplings every timestep.

Repair stage A changes that to `prepare once -> step many`: the immutable assembly is validated once per lifecycle phase, compiled matrices are reused, and an independent reference matrix set is freshly rebuilt once from canonical couplings and then reused. The same midpoint equations and per-step force/timestep/state/refinement guards remain active.

### Stage B — Bridge2 mixed-runtime nested validation

After stage A, current-source-equivalent profiling showed the dominant cost moved to:

```text
mixed_runtime ~= 5.24 s of ~5.69 s total (500-part local case)
```

`Runtime.step()` already begins with a full `validate_session(session, registry)`. It then iterates the five registry regions and called the public `can_execute_region()` for each region. That public function repeats the same full `validate_session(session, registry)` before evaluating one region. Therefore each mixed step redundantly revalidated the same immutable registry/session five additional times.

Repair stage B keeps the public `can_execute_region()` contract unchanged for external callers, but splits the already-validated regional gate logic into a private `_can_execute_region_validated()` helper. `Runtime.step()` performs its existing full validation once, then calls the private helper for each region already proven by that validation. Final next-session validation/checksum remains unchanged.

This is removal of duplicate validation inside one trusted call frame, not removal of validation at the API boundary.

## Bounded optimization plan

Allowed product scope:

1. `scripts/research/fabric_bake0/complex2_settle_rebake_reimpact_v1.gd`
   - validate immutable coupled assembly once per lifecycle phase;
   - build an independent reference matrix set once per phase from canonical couplings;
   - reuse compiled/reference matrices while retaining identical midpoint/state/force guards.
2. `scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd`
   - retain the public `can_execute_region()` full-validation contract;
   - introduce a private regional gate helper that assumes the enclosing `step()` validation already succeeded;
   - eliminate only the five duplicate session/registry validations inside each `step()` call.
3. `.github/workflows/fabric-holdout-r4-g2-linux-double.yml`
   - extend freshness paths to the two Repair R4 runtime files so the final runtime mutation obtains a new exact-head G2/R3/R2/R1 run.
4. This Repair Map.

No physics equation, force schedule, timestep, settle criterion, ringdown length, part count, expected hash, tolerance, representation contract, or performance budget may change.

## Forbidden scope

Do not change:

- `CASE_BUDGET_US` / `LOCAL_REBAKE_BUDGET_US`;
- `MAX_SETTLE_STEPS`, impact/ringdown counts, `DT`, forces, energy/speed thresholds;
- coupled mass/stiffness/damping/coupling constants;
- Bridge2 public failure semantics, source/authority gates, invalidation behavior or checksums;
- G2/R3/R2 event/replay semantics;
- frozen G1 evidence;
- canonical legacy serialization;
- acceptance policy to waive the failing gate.

## Correctness invariants

The reference path remains independent of the compiled matrices: reference matrices are freshly reconstructed from `assembly["couplings"]` before each lifecycle loop and cached only because the system matrices are time-invariant for the phase.

Every coupled timestep still executes `_midpoint_step()`, which validates delta, force vector/range and state/refinement bounds before and after integration.

Every public Bridge2 `can_execute_region()` call still performs the same complete `validate_session()` first. `Runtime.step()` still performs full input-session validation and full output-session validation; only nested repetitions of the already-successful input validation are removed.

## Implementer focused evidence before final publication

Canonical Linux double Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
sha256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

After stage A only, local current-source-equivalent PERF passed `62/62`, with the 500-part case around 5.69 s. Historical local evidence before Repair R4 was already around 5.9 s, so this must not be misrepresented as the server improvement.

After stage B, on the same local environment:

```text
500  total = 2465926 us; mixed_runtime = 2065590 us
1000 total = 2405068 us; mixed_runtime = 1997626 us
2000 total = 2408947 us; mixed_runtime = 1986757 us
COMPLEX2PERF_MATRIX_HASH = 698486abd097e6ee12731b0afb1c6e28ed24bf72b52d8d940c9f5b7336498607
PERF = PASS (62 assertions)
```

Semantic regression controls on the same source-equivalent checkout:

```text
BRIDGE-2 = PASS (125 assertions)
COMPLEX2 = PASS (2115 assertions)
COMPLEX2_EXPERIMENT_HASH = 7017c4acf32ff0f8e75165e1bd8a9c9c45e111ba767776f9ab8b486a52cae541
COMPLEX2-C = PASS (66 assertions)
COMPLEX2C_EXPERIMENT_HASH = 433345db30f8b59e5da67d83cc3a737f546305563029f0f38ca583988e96a995
COMPLEX2-E = PASS (47 assertions)
COMPLEX2E_EXPERIMENT_HASH = 77c3c1e792d082391c8901d9c61946b0655c4abd332f71dc4554ef479fc9a5f8
```

This evidence is Implementer/local evidence only. The checkout is source-equivalent for the changed files but is not to be mislabeled as the final Git HEAD. Authoritative exact-head self-hosted CI is required below.

## Acceptance

Repair R4 is implementation-complete only if the final exact product HEAD satisfies:

1. `FABRIC COMPLEX2-PERF Scaling Acceptance: PASS` for 500/1000/2000 with unchanged `12,000,000 us` budget;
2. `FABRIC B0.6-CLOSE Linux Double = PASS`;
3. `FABRIC COMPLEX2-E Settle Rebake Re-impact Linux Double = PASS`;
4. `FABRIC COMPLEX2-C Coupled Motion Linux Double = PASS`;
5. Bridge2 / Complex2 semantic regression remains PASS with unchanged deterministic hashes;
6. exact G2/R3/R2/R1 runner remains PASS on the final HEAD;
7. no threshold/golden/physics weakening;
8. any review/evidence tied to an earlier product HEAD is stale and must be regenerated on the final HEAD.

Production freeze, unseen holdout, R4 acceptance and SCALE-R5 remain locked until fresh Reviewer + Verifier + Director closure.
