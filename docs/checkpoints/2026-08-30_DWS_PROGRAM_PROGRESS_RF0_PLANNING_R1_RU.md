# DWS — Program Progress Snapshot 2026-08-30 / RF0 Planning R1

**Purpose:** immutable human-readable checkpoint of project direction after SM1 R9 runtime merge and before RF runtime implementation.  
**Canonical main:** `acb9379cacc413fc25a65117fb1627f5a01b9736`  
**Main tree:** `7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68`.

> This snapshot records observed Git state and planning decisions. It does not itself accept SM1, activate P7 or authorize RF runtime mutation.

## 1. What is already done

### Product foundation

- P4 Real Resource Construction — ACCEPTED;
- P5 Equipment / Tools — ACCEPTED;
- P6 Persistent Shared Outpost — ACCEPTED;
- Edge Gateway Foundation — ACCEPTED;
- canonical Item Graph / Construction / persistence owners preserved;
- server restart/reconnect foundations preserved.

### Seamless networking

- SM1 R9 exact runtime verified;
- A↔B authority handoff semantics preserved;
- stable player/entity identity;
- monotonic AuthorityEpoch;
- WARM target zero-write;
- stale source fail-closed;
- stable Gateway endpoint;
- reconnect/recovery and full regression evidence;
- runtime merged to main through PR #327.

SM1 checkpoint acceptance is still pending separate control closure in PR #326.

### Distributed foundations already available

- M0 multi-aggregate transaction/outbox;
- M6 durable gameplay recovery;
- MW6 Matter replication;
- MW7 regional interest replication;
- MW8 authority handoff;
- MW9 durable handoff recovery;
- MW10 cross-region transactions;
- S1 proposal-only distributed compute;
- RL representation/LOD foundation;
- EG4 interest/projection aggregation.

## 2. What is being done now

### Product

`SM1 canonical acceptance/control reconciliation` is the current product gate.

### Architecture

`RF0 Replication Semantic Boundary` is being documented only. No runtime implementation is authorized.

### Research

- ECO parallel performance/reproduction train: PRs #323 → #324 → #325;
- FABRIC compositional-world research: PR #317;
- NX.C1 owner-authority candidate remains a separate opt-in verification line: PR #97.

## 3. What happens next

```text
SM1 canonical acceptance
    ↓
P7 bounded authoritative terrain/material mutation
    ↓
V0 PLAYABLE SEAMLESS PLANET graphical/product acceptance
    ↓
P8 first mobile construct
    ↓
RF1 shadow retained replica cache
    ↓
RF2 first read-only projection consumer
    ↓
static N-authority scale
    ↓
Placement Observatory / SHADOW
    ↓
dynamic placement / split / merge only after proof
```

RF0 sits beside the SM1→P7 transition as an architecture guardrail and does not block P7.

## 4. Key checkpoints

| Checkpoint | State | Meaning |
|---|---|---|
| P4 | ACCEPTED | real resource-backed Construction |
| P5 | ACCEPTED | equipment/tools in playable loop |
| P6 | ACCEPTED | persistent shared outpost + reconnect/restart |
| Edge Gateway | ACCEPTED | stable client edge, routing-only |
| SM1 runtime R9 | MERGED | verified seamless A↔B runtime is in main |
| SM1 checkpoint | PENDING | control acceptance still separate |
| RF0 | PLANNED / DOCS | semantic replication boundary only |
| P7 | NEXT RUNTIME | bounded authoritative terrain mutation |
| V0 Seamless Planet | FUTURE KEY MILESTONE | working bounded persistent seamless surface |
| P8 | FUTURE | first mobile construct |
| RF1 | FUTURE | shadow bounded retained replica cache |
| RF2 | FUTURE | first read-only consumer migration |
| PO0 | FUTURE SHADOW | placement telemetry/proposals only |
| Dynamic placement | DEFERRED | only after static N-authority proof |

## 5. Replication Foundation decision

The new feature is deliberately split into a small train:

```text
RF0 — semantic boundary
RF1 — shadow retained cache
RF2 — one read-only consumer
```

Do not expand this into RF3-RF9 without measured need.

Fundamental invariants:

```text
REPLICATION IS NOT AUTHORITY
CACHE IS NOT PERSISTENCE
INTEREST IS NOT ACTIVATION
SERVER PROCESS IS NOT WORLD IDENTITY
```

## 6. Future RF implementation entry checklist

Before RF1 implementation an agent must:

1. fetch current main and current registry/control truth;
2. verify SM1 acceptance state and current V0 mutation lease;
3. read ADR-021 and the RF roadmap amendment;
4. map current Authority/Directory/Persistence/Gateway owners;
5. locate current replication contracts and domain-specific paths;
6. prove no new canonical owner is introduced;
7. freeze exact RF1 Work Order, risk and acceptance matrix;
8. keep legacy replication client-visible and add shadow publication only;
9. run parity/stale/duplicate/gap/bounds/rebuild tests;
10. perform process-kill lifecycle-decoupling proof;
11. freeze exact runtime head;
12. complete independent review/verification before any consumer migration.

Before RF2:

1. RF1 accepted shadow evidence exists;
2. select one read-only projection consumer;
3. keep player command/movement fast path unchanged;
4. preserve legacy fallback;
5. prove projection parity and outage isolation.

## 7. Complexity ceiling

RF0/RF1 must fail architecture review if they require, without measured proof:

- a new persistent database;
- mandatory external broker;
- new canonical owner;
- new Gateway authority;
- new input network hop;
- dynamic placement;
- split/merge;
- wholesale rewrite of SM1/MW7/NX8.

## 8. Documents to read when resuming

Primary current docs:

- `docs/control/CURRENT_PROJECT_FRONTIERS_RU.md`;
- `docs/plans/V0_CURRENT_WORK_MAP_RU.md`;
- `docs/plans/DWS_REPLICATION_FOUNDATION_ROADMAP_AMENDMENT_RU.md`;
- `docs/architecture/adr/ADR-021-non-canonical-replication-plane.md`;
- `docs/architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md`;
- `docs/network/NETWORK_EXPERIENCE_ROADMAP_NX0_NX9_RU.md`.

These documents are intended to let a fresh agent recover not only the next task, but the reasoning and ownership boundaries behind it.