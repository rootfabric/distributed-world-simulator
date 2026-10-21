# FABRIC R5.6.1 R2 — Fresh Semantic Review, COM Recovery

Дата: 2026-10-21.

**REVIEWER_RESULT: PASS_WITH_NONBLOCKING_FINDINGS (in tested R2 research model)**. **Not a separate-actor review approval**; reviewer and verifier worktrees were separate, but coordinated in one assistant session.

## Exact subject

- HEAD: `60f193d6602d2d6ebb62393d3db6633b14623627` / TREE: `1a92363e7cc159fef4c42e3443542ebb00a71464`.
- RED parent: `91223acb7bf79c37e12fc11d44054ad3e2732455`.
- New release semantics since RED: `apply_owner_verified` checks only the zero-order Fenwick mass prefix when validating Matter mass, avoiding a dependency on the previous COM's Float64 representability.

## Static review observations

- `apply_owner_verified` still checks source checksum, monotonically incrementing revision, Part validation, unique/sorted changed IDs, exact cached old mass/coordinates, finite ten moments, projected total mass and every staged Fenwick node before publishing.
- New mass-prefix path is bounded by a Fenwick traversal (`O(log N)`) rather than running `query_range(0,N)`; existing COM and inertia publication guards in `query_range` remain untouched.
- No FABRIC world writer: R2 session receives canonical source revisions from the genuine `ConstructionConstructStore` and validates external mutations before accepting the index revision.
- Fenced errors return before changing index nodes; replay still rejected after update. No new physical kernel or Construction/Matter changes relative to earlier accepted components.

## Newly authored independent adversarial test

**Test:** `review_r56_r2_multi_range_com_recovery.gd`, SHA256 `5f661cbcc17ed7f3f96f439f3db64a077900ade610f31f5d2df426e025679d52`, exact identical code on RED parent and repaired HEAD. Canonical Linux Godot 4.7.1 double.

- **RED parent**: exit 1, **38 checks / 8 failures**. Legitimate recovery from an unsupported center cannot advance the index; downstream revision and queries remain stale.
- **HEAD GREEN**: exit 0, **51 checks / 0 failures**. With a 4-part canonical source, disjoint ranges A and B independently enter the center-precision unsafe state and return to safe; the unaffected range can still be read during the other range's invalid interval. Four separate revisions commit, published centers and inertia agree with independent centered oracle, unsupported range fails closed, bad Matter and replay leave index status unchanged, `update_full_moment_scans==0`.

Observations on green run: A withheld `R56_R2_RANGE_CENTER_PRECISION_UNSAFE`; B unaffected query PASS; A recovery PASS; B withheld `R56_R2_RANGE_CENTER_PRECISION_UNSAFE`; B recovery PASS.

## Reviewer findings / boundaries

- PASS for this fixed point-mass model and the bounded 1µm **absolute COM representation-conversion** envelope. It is **not** a rigorous claim that full Fenwick floating-point dynamics stays within 1µm under arbitrary masses or arbitrary 100k topology.
- Frozen origin does not track a moving or reparented source origin, by design; numeric failure remains acceptable when geometry becomes ill-conditioned.
- Complete Construction validation, canonical hashing, owner mutation and BRIDGE-4 graph generation may be O(N); only the Fenwick moment update is O(k log N).
- Source Store type/instance identity is only local in-process admission, not network server authentication.
- Cold restart, durable receipts, multi-event network authority, generic rigid-body rotational inertia and true world integration are future gates.

No reproducing new blocker was found in the reviewed bounded contract. **Separate, fresh Reviewer/Verifier actors and human authorization remain required for MERGE_READY** by the project's chosen acceptance protocol.
