# Distributed World Simulator — Harness Snapshot R3

Snapshot ID: `HARNESS-SNAPSHOT-R3`
Captured: `2026-08-18`
Status: `VALIDATED_CANDIDATE_NOT_CANONICAL_MAIN`

Source repository: `rootfabric/distributed-world-simulator`
Source base main: `598e92bb29a147bf12208d8549ddecaa4c9781ab`
Source candidate branch: `control/harness-continuation-hygiene-r1`
Exact source candidate HEAD: `580c9453f205170600c5d8d2f596617d090359f4`
Project Control: run `32102853947 — SUCCESS`
Pull Request: `#131`
Snapshot branch: `control/harness-development-snapshot-r3`

Lineage:

```text
HARNESS-SNAPSHOT-R1
  control/harness-development-protocol-r1
  4b9e6c2c9428f59860368ccad6cf1a561f28206e
        ↓
HARNESS-SNAPSHOT-R2
  source main d9a1a3ca03016d6851a258ff93d5c260a86c5b4c
  snapshot branch control/harness-development-snapshot-r2
        ↓ 11 commits from R2 source
HARNESS-SNAPSHOT-R3
  source candidate 580c9453f205170600c5d8d2f596617d090359f4
```

R3 captures the first DWS Harness state with both:
- explicit mission/role continuation routing;
- instruction hygiene, rule lifecycle and negative self-tests.

This snapshot is a historical/reference branch. It must not be merged back into `main` as a product change. PR #131 remains the integration carrier and still requires fresh independent durable review.

Detailed extraction and lineage notes:
`docs/control/HARNESS_SNAPSHOT_R3_RU.md`

Machine manifest:
`config/control/harness/snapshot-manifest.v1.json`
