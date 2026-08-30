# Distributed World Simulator — Current Project Frontiers

**Refresh date:** 2026-08-30  
**Canonical main:** `acb9379cacc413fc25a65117fb1627f5a01b9736`  
**Main tree:** `7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68`  
**Purpose:** human-readable routing snapshot. Machine acceptance truth remains in `config/control/**`.

> Branch existence or an open PR does not mean that branch is an active product frontier. Historical repair/evidence carriers are grouped separately.

## 1. Product critical path

```text
P4 ACCEPTED
  ↓
P5 ACCEPTED
  ↓
P6 ACCEPTED
  ↓
Edge Gateway Foundation ACCEPTED
  ↓
SM1 runtime MERGED TO MAIN
  ↓
SM1 checkpoint acceptance / control reconciliation   CURRENT PRODUCT GATE
  ↓
RF0 semantic boundary                               architecture-only, non-blocking
  ↓
P7 bounded terrain mutation                         NEXT RUNTIME PRODUCT CHECKPOINT
  ↓
V0 PLAYABLE SEAMLESS PLANET                         key product milestone
  ↓
P8 first mobile construct
  ↓
RF1/RF2 retained replication adoption
  ↓
static N-authority scale
  ↓
dynamic placement later
```

## 2. V0 / SM1 — current product frontier

Runtime R9 is already in canonical main through PR #327.

- merged source: `repair/m7-camera-basis-sync-r9`;
- source HEAD: `b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f`;
- main merge: `acb9379cacc413fc25a65117fb1627f5a01b9736`;
- verified tree: `7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68`.

Formal checkpoint closure remains on PR #326:

- branch `control/v0-sm1-b7-final-reconciliation-r2`;
- HEAD `3c7b395d351fa520c144240561b75dd9ef34170d`;
- OPEN / DRAFT at this refresh.

```text
runtime merged != checkpoint accepted
```

P7 must not start until SM1 acceptance is durably reconciled or main records an explicit superseding decision.

Historical SM1 repair/control PRs #282-#322 remain evidence/forensics carriers. They are not independent active runtime frontiers after R9 merged to main.

## 3. Replication Foundation — newly planned architecture lane

Planning branch: `docs/dws-replication-foundation-roadmap-r1`.

Scope: ADR-021 + RF roadmap amendment + work-map/frontier refresh + NX8/Distributed Runtime cross-links.

No runtime mutation is authorized by this branch.

```text
RF0 semantic boundary         NOW: plan/contracts only
RF1 shadow retained cache     later
RF2 first read-only consumer  later
PO0 placement observer        later / independent / SHADOW
```

RF0 is deliberately non-blocking for P7.

## 4. ECO — active research/performance frontier

Current visible parallel chain:

```text
PAR1 R2  PR #323  feature/eco-evo7-par1-parallel-backend-selection-r2
   ↓
PAR2 R2  PR #324  feature/eco-evo7-par2-parallel-only-recruitment-r2
   ↓
PAR3 R2  PR #325  feature/eco-evo7-par3-parallel-candidate-reproduction-r2
```

Current PAR3 head at refresh: `735b3fd40cf18337fa33f51c79578dd5c03aab42`.

ECO remains research/non-blocking for V0 unless main registers an explicit dependency.

## 5. FABRIC — active research frontier

PR #317: `research/fabric0-compositional-world-fabric-r1`, HEAD `e011a794ef2e631fc285c9958a17f3a6a050408f` at refresh.

FABRIC experiments remain separate from V0/RF authority and persistence ownership.

## 6. NX — bounded convergence candidate

PR #97 remains open/draft: `feature/h0-2-nx-c1-owner-authority-r3`, HEAD `1a56fe0e845c941f14ce7b9296ee939e9d0ca8bc`.

NX.C1 remains opt-in and does not replace the current SERVER_PREDICTED V0 baseline until its own verification/acceptance closes.

NX8 remains the future owner of interest-management and replication-budget policy. RF does not replace NX8; RF supplies publication/retention semantics that NX8 may consume.

## 7. Stable/frozen foundations

- Matter: MW10 accepted stable baseline;
- S1 Distributed Compute: stable proposal-only worker foundation;
- Construction composition T1B: accepted/frozen evidence;
- G8 World Generation: accepted/frozen baseline in project registry;
- Edge Gateway Foundation: accepted and consumed by P6/SM1.

Do not restart these as new foundations when implementing P7/RF.

## 8. Research donors, not product bases

SM0 seamless handoff, historical research SM1-I2, MRPF/H and RL research may donate contracts/ideas/tests. Wholesale research merges into product lineage remain forbidden unless main explicitly selects a bounded integration.

## 9. What is actually being done next

```text
1. Close SM1 canonical acceptance/control reconciliation.
2. Merge/review RF roadmap documentation; no runtime mutation.
3. Activate P7 from the exact accepted SM1 successor base.
4. Build bounded authoritative terrain/material mutation.
5. Prove two-client + reconnect/restart + seam continuity.
6. Reach V0 PLAYABLE SEAMLESS PLANET graphical checkpoint.
7. Continue P8.
8. Start RF1 shadow cache when product sequencing permits.
9. RF2 migrates one read-only projection consumer.
10. Only later evaluate static-N scale and dynamic placement.
```

## 10. Stop conditions

Stop and return to architecture/control if implementation requires a second Item Graph/Construction/Persistence/Directory/Authority owner, Gateway canonical gameplay state, client-private terrain truth, S1 Worker authoritative publication, RF cache as recovery truth, mandatory new broker/database for RF0/RF1, dynamic split/merge before static correctness, or a successor runtime before predecessor acceptance.