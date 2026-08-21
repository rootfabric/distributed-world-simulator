# V0-SM0 P4 — Prewarmed Fast Handoff Design Brief

Status: **DESIGN BRIEF / CRITICAL / HUMAN GATE BEFORE RUNTIME MUTATION**.

Scope: branch-local SM0 two-authority lab only. This document does not promote a production World Directory, zone-balancer or new global authority foundation.

## 1. Problem statement

P3 proved a healthy localhost handoff with stable logical/player identity and no perceptible transfer hitch.

P3.1 added deterministic UDP egress latency on authority A, authority B and the graphical client. At `30 ms` one-way (`~60 ms` configured RTT), the operator reported a small but perceptible pause at the authority boundary while movement after activation remained stable.

The visible DEFAULT excerpt at exact HEAD `4e961898a7418c9d14a167df7f789502f4d2c250` contains complete handoff totals of `146, 171, 146, 176, 146, 153 ms` for the first six crossings, with `identity_changes=0`, `player/a` unchanged and movement magnitude `0.25`.

The P3.1 FINAL WAN matrix is the next objective measurement gate. P4 is prepared now as a design-only continuation so protocol mutation does not begin without an explicit model and review route.

## 2. Risk classification

**CRITICAL**.

Reason: P4 changes cross-server authority handoff sequencing. Canonical `risk-policy.v1.json` lists `CROSS_SERVER_AUTHORITY_CHANGE` as a CRITICAL minimum trigger.

Required route before runtime acceptance:

```text
IMPLEMENTER
  + REVIEWER
  + VERIFIER
  + DIRECTOR
  + HUMAN
```

The current document satisfies the required pre-build Design Brief only. It is not authorization to mutate runtime.

## 3. Current behavior

Current source authority sequence after an accepted move reaches the foreign side of `x=0`:

```text
CLIENT_MOVE
  ↓
source authoritative move accepted
  ↓
MOVE_ACK sent to client
  ↓
source freezes player
  ↓
PLAYER_HANDOFF_PREPARE → target
  ↓
PLAYER_HANDOFF_PREPARED ← target
  ↓
source retires local writer
  ↓
PLAYER_HANDOFF_COMMIT → target
HANDOFF_REDIRECT       → client     (parallel)
  ↓
client switches route
  ↓
CLIENT_ACTIVATE → target
  ↓
ACTIVATE_ACK ← target
```

Important existing correctness properties:

- source is the only canonical writer before retirement;
- target stores PREPARE state but does not become the active writer before COMMIT;
- source retires before target activation;
- target requires a committed transfer before client activation;
- delayed/duplicate PREPARE and COMMIT paths are replay-safe in the bounded lab;
- source redirect ACK and target COMMIT ACK may arrive in either order;
- stable `logical_player_id`, `player_entity_id`, input sequence and directory epoch are enforced.

## 4. Why latency grows

The current protocol starts PREPARE only after the boundary-crossing move is already accepted.

Under a symmetric one-way network delay `L`, the post-crossing critical path contains approximately:

```text
source → target PREPARE        L
 target → source PREPARED      L
 source → client REDIRECT      L
 client → target ACTIVATE      L
 target → client ACTIVATE_ACK  L
```

COMMIT can overlap the redirect/activation path, so the practical total is not a rigid `5L`, but the P3.1 DEFAULT observations are consistent with several serial one-way legs becoming visible once `L=30 ms`.

The first optimization target is therefore not interpolation cosmetics. It is removing the PREPARE round trip from the post-crossing critical path while preserving single-writer authority.

## 5. Desired behavior

P4 should:

1. reserve/validate the target authority **before** the player crosses the boundary;
2. keep the source as the only canonical writer while prewarming;
3. avoid creating a second active player authority on the target;
4. allow the final authoritative state package to be committed without a post-crossing PREPARE RTT;
5. preserve the existing safe path as a fallback when prewarm is absent, stale or rejected;
6. keep client identity, input sequence, authority epoch and player state continuity unchanged;
7. reduce objective controlled-WAN handoff latency before adding presentation-only masking.

## 6. Alternatives considered

### A. Visual smoothing only

Continue rendering the old position or interpolate through the pause while the current authority protocol remains unchanged.

Rejected as the first P4 move because it hides the symptom without reducing the authority critical path. It can be a later presentation layer after protocol latency is reduced.

### B. Client preconnect only

Open/select the target UDP route before the crossing but leave source→target PREPARE after the crossing.

Rejected as insufficient. UDP route selection is cheap in this lab; the dominant serialized authority PREPARE RTT remains.

### C. Dual-writer overlap

Let source and target both accept authoritative movement during an overlap band and reconcile later.

Rejected. This violates the strongest proven SM0 invariant and creates duplicate canonical truth.

### D. Prewarmed target reservation + final fast commit

Before crossing, source asks target to reserve the next authority epoch for the stable player identity without activating or importing canonical player state. At crossing, source sends the final immutable handoff package directly in the commit message and redirects the client in parallel.

**Selected design.**

It removes the post-crossing PREPARE RTT without introducing dual writers or stale continuously mirrored player state.

## 7. Selected P4 design

### 7.1 Prewarm band

While the source remains on its owned side of the boundary and there is no active transfer, entering a bounded branch-local prewarm band starts a reservation.

Initial SM0 lab value:

```text
PREWARM_DISTANCE = 1.0
```

For Zone A, prewarm is eligible while `-1.0 <= x < 0.0`.
For Zone B, prewarm is eligible while `0.0 <= x <= 1.0`.

This is intentionally a lab constant, not a production world partitioning contract.

### 7.2 Reservation identity

The source creates a prewarm record containing only routing/authority metadata:

```text
prewarm_id
logical_player_id
player_entity_id
source_authority_id
target_authority_id
source_zone_id
target_zone_id
source_authority_epoch
target_authority_epoch
source_directory_revision
expires_at_msec
```

It does **not** transfer active canonical player state and does not change directory ownership.

### 7.3 New control messages

Proposed branch-local messages:

```text
PLAYER_HANDOFF_PREWARM
PLAYER_HANDOFF_PREWARMED
PLAYER_HANDOFF_PREWARM_CANCEL
PLAYER_HANDOFF_FAST_COMMIT
PLAYER_HANDOFF_COMMITTED
```

`PLAYER_HANDOFF_COMMITTED` may remain the existing commit ACK shape if doing so is unambiguous and replay-safe.

### 7.4 Target prewarm state

Target stores the reservation in a separate non-authoritative map keyed by `prewarm_id`.

Hard rules:

- no `_authority.join()`;
- no canonical player import;
- no directory mutation;
- no client endpoint ownership;
- no target movement acceptance;
- no writer role.

The reservation is only proof that the target has validated the expected source/target epochs, stable identity and compatibility before the crossing.

### 7.5 Prewarm acknowledgement

Target replies `PLAYER_HANDOFF_PREWARMED` only after validating:

- target authority id;
- current source directory owner;
- source authority epoch;
- expected next target epoch;
- stable logical/player identity;
- no conflicting reservation for the same player/epoch.

Source records the acknowledgement but remains the active writer.

### 7.6 Leaving the prewarm band

If the player moves away from the boundary before crossing:

- source may send best-effort `PLAYER_HANDOFF_PREWARM_CANCEL`;
- target also expires the reservation by bounded TTL;
- no directory or player state rollback is needed because prewarm never owned canonical truth.

### 7.7 Boundary crossing fast path

When a move actually crosses the boundary and a matching fresh prewarm ACK exists:

1. source builds the same validated immutable final handoff package from the boundary-crossing canonical player state;
2. source freezes the player;
3. source retires its canonical writer using the existing leave semantics;
4. source advances its local directory to the target epoch exactly as today;
5. source sends `PLAYER_HANDOFF_FAST_COMMIT` containing:
   - `prewarm_id`;
   - the complete final handoff package;
   - the committed directory;
6. source sends `HANDOFF_REDIRECT` to the client in parallel;
7. target validates reservation + final package + checksum + committed directory;
8. only then target imports/activates canonical player authority;
9. target ACKs the source and handles the client activation through the existing identity/epoch gates.

The client protocol can initially remain unchanged.

### 7.8 Expected post-crossing critical path

With a successful prewarm, the removed PREPARE RTT leaves approximately:

```text
source → target FAST_COMMIT     L
source → client REDIRECT        L   (parallel with commit)
client → target ACTIVATE        L
 target → client ACTIVATE_ACK   L
```

Because FAST_COMMIT and REDIRECT start together, target commit should normally arrive before the client ACTIVATE request on symmetric links.

For `L=30 ms`, a branch-local objective total around three serialized one-way legs plus processing (`~90 ms` order of magnitude) is plausible, versus the current observed `~146-176 ms` excerpt. This is a design expectation, not an acceptance claim.

## 8. Race handling

### ACTIVATE arrives before FAST_COMMIT

Do not fail the whole client state and do not activate early.

Preferred bounded behavior:

- hold the exact ACTIVATE request as pending for the matching `transfer_id/prewarm_id` for a short timeout;
- complete it immediately after a valid FAST_COMMIT;
- reject on timeout or identity/epoch mismatch.

Alternative acceptable first implementation: keep the current `SM0_TARGET_NOT_COMMITTED` retry behavior. It is correct but may reduce the latency win on asymmetric/reordered links.

### Duplicate PREWARM

Exact same reservation is idempotent and re-ACKed.
Conflicting identity/epoch metadata is rejected.

### Duplicate FAST_COMMIT

Exact same final package/checksum is replayed from committed transfer state.
A conflicting final package for the same reservation is an invariant violation.

### Late PREWARM after fallback started

Ignore or reject without altering the active legacy transfer.

## 9. Fallback path

If any of the following is true at boundary crossing:

- no prewarm ACK;
- reservation expired;
- epoch/directory changed;
- target rejected prewarm;
- reservation identity mismatch;

then the source uses the existing proven P3/P3.1 `PREPARE → PREPARED → COMMIT` path unchanged.

P4 must fail **closed to the existing safe path**, never fail open into dual authority.

## 10. Canonical truth / ownership rules

P4 must not introduce:

- a second World Directory implementation;
- a second canonical player store;
- target-side active player truth during prewarm;
- a new global zone registry;
- client-owned canonical movement;
- duplicate ownership epoch writers.

Prewarm metadata is ephemeral protocol state only.

## 11. Expected changed surfaces for implementation

Likely bounded runtime surfaces:

```text
scripts/runtime/seamless/sm0/sm0_contracts.gd
scripts/runtime/seamless/sm0/sm0_authority_server_node_v2.gd
scripts/runtime/seamless/sm0/sm0_manual_client_node.gd        # instrumentation only if needed
tests/runtime/... SM0 focused protocol fixtures
RUN_V0_SM0_* P4 acceptance runner / analyzer
```

The implementation should prefer extending `sm0_authority_server_node_v2.gd` rather than rewriting the proven base state machine.

## 12. Validation plan

Before any P4 acceptance claim:

### Contract/focused

- PREWARM validation and exact replay;
- conflicting PREWARM rejected;
- expiry/cancel leaves no canonical mutation;
- FAST_COMMIT requires matching fresh prewarm;
- FAST_COMMIT exact replay;
- conflicting FAST_COMMIT rejected;
- source remains sole writer before retirement;
- target becomes writer only after valid fast commit;
- fallback uses the existing PREPARE path unchanged.

### Identity/state

Across repeated A↔B crossings:

- `logical_player_id` unchanged;
- `player_entity_id` unchanged;
- authority epoch monotonic;
- ownership epoch semantics unchanged;
- input sequence never resets;
- final position/velocity/orientation preserved;
- source and target never simultaneously expose active writer truth.

### Faults

- delayed PREWARM ACK;
- dropped PREWARM ACK;
- duplicate PREWARM;
- stale reservation;
- delayed FAST_COMMIT;
- duplicate FAST_COMMIT;
- ACTIVATE-before-COMMIT race;
- client redirect retry;
- target unavailable after prewarm;
- source remains fail-closed with precise invariant/error evidence.

### Controlled WAN

Re-run the P3.1 matrix profile set on the P4 exact head:

```text
10 +/-2 ms
20 +/-3 ms
30 +/-5 ms
45 +/-7 ms
```

Required comparison is exact-profile old path vs P4 fast path.

Primary objective metric:

```text
boundary MOVE_ACK trigger → ACTIVATE_ACK
```

Secondary metrics:

```text
prewarm lead time
prewarm hit rate
fast-path rate
fallback rate
trigger→redirect
redirect→activate
A→B / B→A symmetry
identity changes
source/target writer overlap violations
```

## 13. Post-build critique questions

After implementation, explicitly check:

- did reservation become duplicate directory truth?
- did prewarm accidentally create target player state?
- can a sibling path commit without source retirement?
- can stale prewarm authorize a later epoch?
- can two reservations exist for the same player/epoch?
- can delayed packets revive a retired source?
- can fallback and fast path both commit the same crossing?
- can ACTIVATE create authority before committed directory ownership?
- did the fast path weaken current duplicate/replay safety?

## 14. Non-goals

P4 does not yet implement:

- production geographic zone discovery;
- dynamic server selection/load balancing;
- NATS/JetStream;
- global World Directory;
- cross-zone Construction/Matter transactions;
- packet loss/reorder optimization beyond correctness;
- client-side movement prediction through the handoff;
- visual ghost overlap/interpolation masking.

Those remain separate later convergence steps.

## 15. Human gate

The selected design changes cross-server authority sequencing and therefore requires an explicit human gate before runtime mutation.

Recommended decision after the P3.1 FINAL matrix:

```text
APPROVE P4 DESIGN D:
prewarmed target reservation + final fast commit + safe fallback to the existing PREPARE path.
```

Reason: it attacks the measured authority critical path while preserving the single-writer invariant and avoiding continuous duplicate player state on the target.
