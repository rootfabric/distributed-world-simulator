# EVO ARCH2 A7 — Main Integration Repair R3

Дата: 2026-09-13. Work Order: `EVO-ARCH2-A7-MAIN-INTEGRATION-20260913-R1`.

## Finding

Fresh integration review finding `3998382558` correctly identified a fail-open provenance pattern: candidate `verify.py` compared transferred paths with SHA values stored in candidate-owned `expected-transfer.v1.json`, but did not independently require that those objects equal `ACCEPTED_A7:path`. Candidate and manifest could therefore drift together.

The review also observed that the accepted commit was not guaranteed to be present in a checkout of the disjoint current-main integration branch.

## Repair

Canonical source authority remains:

```text
ref  = refs/remotes/origin/acceptance/eco-evo-arch2-a7-r1
HEAD = 8eccf6304078bec3a3ccaa5860c5aab6ee311209
TREE = 24e876b7377cb3e1e521f08ff9766331fe4e895a
```

Every canonical static/exact integration workflow must explicitly fetch this ref read-only before validation. The candidate verifier then fail-closes unless:

1. the remote-tracking acceptance ref exists;
2. its commit equals exact accepted HEAD;
3. its commit tree equals exact accepted TREE;
4. each transferred subtree/blob object satisfies `HEAD:path == ACCEPTED_A7:path`;
5. candidate manifest SHA, if present, also equals that direct accepted object.

Thus `expected-transfer.v1.json` is an audit-friendly redundant pin, not authority by itself.

Repair R2 finding `3998382556` is already addressed by exact accepted morphology model/renderer blobs. Both review findings require a fresh final HEAD/TREE, static/exact runs and independent exact-head review after R3.

No production/network/simulation/control/architecture file is touched. No main merge is authorized by this repair.
