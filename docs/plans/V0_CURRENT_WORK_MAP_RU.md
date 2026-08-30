# V0 — Current Primary Work Map

**Refresh:** 2026-08-30  
**Canonical main:** `acb9379cacc413fc25a65117fb1627f5a01b9736`  
**Current product gate:** SM1 canonical acceptance/control reconciliation  
**Next runtime checkpoint after acceptance:** `V0_P7_BOUNDED_TERRAIN_MUTATION`

> This is a human-readable routing map. Machine eligibility and acceptance remain owned by `config/control/**`.

## 1. Current product state

```text
P4 Real Resource Construction       ACCEPTED
    ↓
P5 Equipment / Tools                ACCEPTED
    ↓
P6 Persistent Shared Outpost        ACCEPTED
    ↓
Edge Gateway Foundation             ACCEPTED
    ↓
SM1 Seamless Product Integration    RUNTIME MERGED / CHECKPOINT ACCEPTANCE PENDING
    ↓
P7 Bounded Terrain Mutation         NEXT AFTER SM1 ACCEPTANCE
    ↓
V0 PLAYABLE SEAMLESS PLANET         KEY PRODUCT MILESTONE
    ↓
P8 First Mobile Construct           FUTURE
```

## 2. Exact SM1 state

Verified R9 runtime is now in `main` through PR #327.

```text
R9 source HEAD   b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
R9 / main tree   7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68
main merge       acb9379cacc413fc25a65117fb1627f5a01b9736
```

Runtime evidence already includes Windows validation, fresh Verifier and fresh Reviewer. The remaining product gate is canonical control/acceptance reconciliation.

Current closure carrier:

```text
PR #326
control/v0-sm1-b7-final-reconciliation-r2
HEAD 3c7b395d351fa520c144240561b75dd9ef34170d
OPEN / DRAFT
```

Do not infer checkpoint acceptance from runtime merge.

## 3. New architecture insertion — Replication Foundation

New plan:

`docs/plans/DWS_REPLICATION_FOUNDATION_ROADMAP_AMENDMENT_RU.md`

Architecture decision:

`docs/architecture/adr/ADR-021-non-canonical-replication-plane.md`

The insertion is intentionally non-disruptive:

```text
SM1 checkpoint accepted
    │
    ├── RF0 Replication Semantic Boundary
    │      docs/contracts only
    │      does not consume V0 runtime mutation lease
    │      does not block P7
    │
    ▼
P7
    ↓
P8
    ↓
RF1 Shadow Retained Replica Cache
    ↓
RF2 First Read-Only Consumer
```

RF0 prevents future P7/P8 code from creating direct process-lifetime dependencies without forcing a new service today.

## 4. P7 — next runtime checkpoint

P7 remains the next product runtime stage after formal SM1 acceptance.

Goal:

```text
equipped tool
→ authoritative dig command
→ canonical terrain/Matter mutation
→ material/resource yield
→ canonical Item Graph
→ two-client convergence
→ reconnect reconstruction
→ server restart reconstruction
→ mutation continuity across A/B seam
```

P7 must reuse:

- accepted P4/P5 resource and equipment semantics;
- canonical Item Graph;
- existing Matter foundation rather than creating V0-private terrain truth;
- accepted Gateway path;
- SM1 authority/epoch/handoff semantics;
- existing persistence/recovery owners;
- RF0 semantic rule that replication is read-only/non-canonical.

Explicit P7 non-goals:

- new Gateway;
- dynamic sharding;
- arbitrary-N balancing;
- new persistence database;
- RF1 implementation as a prerequisite;
- P8 mobile construct.

## 5. V0 PLAYABLE SEAMLESS PLANET milestone

After P7, the major product checkpoint must prove a bounded planetary surface where two graphical clients can:

- move and interact in one persistent world;
- mine resources;
- dig/change terrain;
- receive canonical material into Item Graph;
- build from canonical resources;
- cross A/B authority boundary without normal reconnect/respawn/loading;
- continue dig/build after handoff;
- reconnect to the same world state;
- survive server restart recovery;
- converge to one canonical truth.

## 6. P8 — First Mobile Construct

P8 follows the first seamless-planet milestone unless main explicitly changes sequencing.

P8 composes existing Construction, Item Graph, persistence, reference frames and seam-aware authority. It must not redefine them.

## 7. RF1/RF2 later adoption

RF1 starts as shadow-only bounded retained cache. Gameplay stays on legacy paths.

RF2 moves one read-only projection consumer after RF1 proves parity, stale/duplicate/gap fences, bounded memory and total-cache-loss rebuild.

Player input and authoritative movement do not route through RF.

## 8. Dynamic placement remains future

Correct order:

```text
static correctness
→ static N-authority world
→ placement observatory SHADOW
→ dynamic placement
→ split/merge
→ interaction-aware meshing
```

`Replication Plane != Dynamic Server Meshing`.

## 9. Immediate execution order

```text
CURRENT
  SM1 acceptance/control reconciliation

PARALLEL NON-RUNTIME
  RF0 roadmap/ADR review

NEXT PRODUCT RUNTIME
  P7 bounded terrain mutation

THEN
  seamless-planet product acceptance
  P8
  RF1 shadow cache
  RF2 read-only adoption
```

## 10. Fail-closed routing

Stop and replan if a future stage requires:

- second Item Graph;
- second Construction truth;
- second Matter/terrain truth;
- second persistence owner;
- Gateway as canonical owner;
- RF cache as canonical/recovery truth;
- Worker direct canonical publication;
- new AuthorityEpoch owner;
- mandatory broker/service hop without measured need;
- successor product runtime before predecessor acceptance.