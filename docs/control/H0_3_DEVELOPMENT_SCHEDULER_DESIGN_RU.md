# H0.3 — Development Multi-Worker Scheduler Design

**Status:** `H0_3_DESIGN_READY_WITH_REVIEW_CORRECTIONS`  
**Lane:** preparation only; no scheduler implementation or runtime authorization  
**Owner:** HARNESS / MAIN control plane  

## 1. Boundary

H0.3 is a **development Work-Order scheduler/control layer**. It coordinates development agents and their bounded Work Orders. It is not a game-runtime process scheduler, gameplay authority owner, simulation scheduler, game-time owner, or V0 runtime component.

```text
Git/control truth
      ↓
Work Order + scheduler-side normalized candidate
      ↓
path / ownership / dependency / risk audit
      ├─ compatible → ELIGIBLE_FOR_DISPATCH
      └─ conflict   → BLOCK
```

`ELIGIBLE_FOR_DISPATCH` does not itself authorize execution or merge; all existing Director/Human gates remain authoritative.

## 2. Reuse canonical Harness contracts

Current `distributed_world_simulator.work_order.v1` remains authoritative. H0.3 must not silently fork it.

Scheduler may derive an immutable sidecar/normalized `WorkOrderCandidate` from the existing Work Order plus canonical control state:

```text
WorkOrderCandidate
├─ candidate_id
├─ source_work_order_identity
├─ lane_id
├─ main_base_identity
├─ ownership_claims[]
├─ normalized_allowed_paths[]
├─ normalized_watched_paths[]
├─ normalized_critical_watched_paths[]
├─ dependencies[]
├─ canonical risk_class
├─ checkpoint_owner
├─ integration_order
├─ evidence_identity
└─ derived_scheduler_state
```

Promotion of any of these derived fields into a future Work Order schema revision requires a separate bounded H0.3 control Work Order, schema review, migration rule and tests.

## 3. No second risk taxonomy

H0.3 uses the existing machine risk classes only:

```text
LOW
MEDIUM
HIGH
CRITICAL
```

Do not introduce parallel scheduler classes such as `R0/R1/R2/R3`. Scheduler behavior is derived from canonical risk policy plus explicit dependency/ownership facts.

Unknown or malformed risk → fail closed.

## 4. Exact base identity

Every candidate is pinned to exact development/control facts:

```text
repository
canonical_branch
base_sha
control_revision
registry_generation
architecture_revision
scheduler_policy_version/digest
work_order_schema_version/digest
```

Before dispatch, `origin/main` must still equal the candidate base or the candidate enters `REVALIDATE`. Historical source-accepted branches do not authorize stale-base work.

## 5. Path and ownership intersections

Paths are normalized repository-relative, reject absolute/`..`, use deterministic separators/case/glob semantics.

Write/write overlap on mutable paths → `BLOCK/BLOCK` until explicit arbitration.

Ownership is checked independently of filenames. A scheduler-side claim is not allowed to invent canonical ownership. Claims must resolve through current architecture/registry ownership sources.

```text
same canonical truth + WRITE/WRITE → BLOCK
unknown owner                         → BLOCK
ambiguous truth alias                → RED/BLOCK
READ + WRITE                         → allowed only if dependency/watch policy permits
DERIVED_PRESENTATION + WRITE         → allowed only if ownership/dependency/watch audit permits
```

`INDEPENDENT_OF` can never override path, ownership, critical-watch or base-freshness conflicts.

## 6. Dependency semantics

Normalized relations:

```text
A BLOCKS B
A WATCHES B
A INDEPENDENT_OF B
```

`BLOCKS`: consumer cannot become dispatch-eligible until required producer checkpoint/state is satisfied.

`WATCHES`: parallel eligibility is possible, but producer movement inside watched scope triggers consumer revalidation; critical watched movement blocks or invalidates.

Dependency cycles or contradictory relations are `RED/BLOCK`.

## 7. Deterministic audit order

```text
1. exact main/control freshness
2. Work Order/candidate normalization
3. allowed-path overlap
4. canonical ownership intersection
5. directional dependency audit
6. watched/critical-watched movement
7. canonical risk policy
8. evidence namespace isolation
9. dispatch eligibility
```

Risk priority never overrides ownership/path conflicts.

## 8. Evidence isolation and movement

Evidence identity includes at least:

```text
execution_id
lane_id
work_order_id
candidate_id
base_sha
head_sha
evidence root/digest
review receipt
verifier receipt
```

Main movement is audited using the diff from candidate base to fresh main.

- no relevant intersection → recreate/revalidate a fresh-base candidate; old evidence remains historical;
- watched overlap → `REVALIDATE`;
- critical watched overlap → `BLOCK` before run, `INVALIDATED` during run/evidence;
- allowed-path or ownership-source movement → collision/ownership re-audit;
- evidence head mutation → evidence invalidated until fresh review.

## 9. Integration queue

Only evidence-ready lanes may enter the integration queue. Ordering:

```text
hard dependency topology
→ required serialization from path/ownership
→ declared integration order
→ canonical risk policy
→ deterministic candidate_id tie-break
```

Before each integration, re-read fresh main. After each integration, all remaining candidates are re-audited because main moved.

`INTEGRATION_QUEUED != MERGE_AUTHORIZED`.

## 10. Restart-safe reconstruction

Git/control state remains the source of truth. Scheduler restart must reconstruct exact candidate set, conflict graph, dependency graph, lane states, integration queue and Human Attention set.

Same Git/control snapshot must produce the same normalized-state/conflict-graph/integration-queue digests. Mismatch → `RED`, dispatch disabled.

## 11. Human Attention compression

Group downstream symptoms by one root fingerprint containing severity, canonical/checkpoint owner, blocker type, path/truth/dependency key and movement identity. One root cause should produce one Human Attention item with affected lanes, evidence refs, fail-closed default and next legal action. CRITICAL items are never hidden by compression.

## 12. Synthetic H0.3 acceptance

Required fixtures, with no real NET/GEO/ITEM runtime mutations:

```text
NET + GEO independent                    → both dispatch-eligible
GEO + ITEM independent                   → both dispatch-eligible
same runtime write path                  → BLOCK/BLOCK
same canonical WRITE truth               → BLOCK/BLOCK
critical watched change pre-dispatch     → consumer BLOCK
critical watched change during RUN       → INVALIDATED/RED
main moves unrelated                     → fresh-base revalidation succeeds
main moves through watched scope         → REVALIDATE
dependency cycle                         → RED/BLOCK
contradictory INDEPENDENT + owner clash  → RED/BLOCK
unknown owner                            → BLOCK
evidence namespace collision             → RED/BLOCK
dispatch race with main movement         → no dispatch; REVALIDATE
restart from identical Git state         → identical scheduler state digest
```

## 13. Future bounded implementation sequence

Preparation proposes, but does not issue, these future H0.3 Work Orders:

```text
H0.3-W1 candidate normalization + deterministic identity
H0.3-W2 path/watch/ownership intersection auditor
H0.3-W3 dependency planner + canonical risk-policy integration
H0.3-W4 main-movement/evidence invalidation
H0.3-W5 integration queue + restart reconstruction + attention compression
H0.3-W6 synthetic acceptance + independent review/verifier
```

Actual Work Orders, allowed paths and exact base SHA are materialized only after H0.2 reaches its gate and current main/control state is reread.

## Final verdict

```text
H0_3_DESIGN_READY_WITH_REVIEW_CORRECTIONS
runtime_authorized = false
scheduler_implementation_started = false
work_order_schema_changed = false
canonical_risk_policy_changed = false
```
