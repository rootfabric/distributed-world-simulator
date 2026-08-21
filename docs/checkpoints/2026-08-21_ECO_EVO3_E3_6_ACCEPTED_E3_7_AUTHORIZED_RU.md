# ECO EVO3 E3.6 — ACCEPTED / E3.7 AUTHORIZED

Статус: `RESEARCH_ONLY`.

## Принятое основание

- E3.6 PR: `#183`.
- reviewed/verifier HEAD: `b7be11bcc47f68a48056885d4627a1910ef079f7`.
- executable freeze: `82214bf840cddd32d8f012e62f0e790feac3a76b`.
- canonical E3.6 merge: `b7c279ec60a335b91924b3f1f6a0df6ac4f61d1d`.
- exact-head E3.6 Closure: `32457280719 / #8 — SUCCESS`, job `96696942507`, artifact `9437669914`.
- exact-head Project Control: `32457280676 / #1077 — SUCCESS`, job `96696895314`, artifact `9437664359`.
- fresh independent Reviewer PASS: PR #183 comment `#5368463437`.
- fresh independent Verifier PASS: PR #183 comment `#5368669947`.
- Director checkpoint/merge authorization: PR #183 comment `#5368674583`.
- exact-head Evidence Map repair: PR #183 comment `#5366940549`.
- `E3.6-R-EVIDENCE-001 = CLOSED`.

PR #183 was merged with exact expected-head protection: GitHub accepted merge only for `b7be11bcc47f68a48056885d4627a1910ef079f7`. The canonical merge therefore preserves the independently reviewed/verifier-tested candidate with no post-verification executable mutation.

## Accepted E3.6 temporal program identity

```text
committed Git blob       fc083dfddbe4142f13ab2a1649cb85c52ea0c652
artifact bytes           18865
artifact SHA-256          0dbeea7185e7667259af3846486b9e4a3350fac4f2e731ad0dc4a0e59e48c9cf
provenance hash           da934ab4ef4eae43c3622806cf6a731dbf4998c85e2721139e80af43ff5a7530
temporal program hash     a2fcb297872c8d7706b854a2cb01bdd25744296f3f94921ab7613c0de8e46908
tests                     23/23
closure predicates        15/15
```

Accepted deterministic replay:

- active E3.5 basis `22`;
- active spatial keys `11`;
- temporal envelopes `11`;
- all 22 basis keys are covered exactly once;
- seasonality state `UNRESOLVED_SINGLE_SNAPSHOT`;
- every observed envelope remains `min = anchor = max`;
- `stable_time_key` remains opaque owner identity, not numeric canonical time;
- future disturbance events `0`;
- canonical history writes `0`;
- individual entities `0`;
- inactive E3.1 `cell-12` is not promoted to population-temporal work.

The accepted authority boundary requires exact retained raw bytes for E3.6 contract + binding + exact accepted E3.5 + exact E3.1 TF/ENV context. Parsed/reconstructed JSON does not acquire serialization authority. Authoritative integrity reparses exact inputs, recomputes semantic identities where defined, independently rebuilds the temporal program and requires canonical byte equality.

## Project Control interpretation

Project Control facts remain exactly:

```text
global       RED
ECO          RED
directional  RED
NX -> ECO    YELLOW / WATCH_HIT
ECO critical directional intersections = 0
critical RED intersections = NX -> V0, V0 -> NX
```

No RED value is renamed or reinterpreted as GREEN/NON_RED.

The main-owned `RESEARCH_DESIGN_FRONTIER` advisory policy permits this bounded research acceptance because no critical ECO intersection is present. It does not authorize production ECO, XFER1, canonical TF/ENV/history ownership, persistence, network or transaction authority.

## Frontier

`ECO.EVO3/E3.6 = ACCEPTED`.

`ECO.EVO3/E3.7 = AUTHORIZED_NOT_STARTED`.

E3.7 is the sequential research successor: deterministic full `PlanetEcologyProgram` compilation from the accepted EVO3 chain and persisted EVO2 catalog. It must prove fresh-process byte/hash stability for identical snapshot/catalog inputs and may not use global RNG or unbound nondeterministic inputs.

This acceptance does **not** itself start E3.7 implementation and does not create an E3.7 Work Order or mutation authority.

## Неподвижные границы

- E3.7 must consume exact accepted predecessor identities; candidate aliases or semantically equivalent reconstruction do not gain authority.
- identical accepted snapshots + catalog must produce identical `PlanetEcologyProgram` bytes/hash.
- global RNG is forbidden; external nondeterministic inputs must be snapshot-bound.
- `PlanetEcologyProgram` remains `RESEARCH_DERIVED_NON_AUTHORITATIVE`.
- canonical G/ENV/MAT/WQ/SD/TF ownership remains external.
- no production persistence/world transaction/network authority is created.
- E3.8 remains `BLOCKED` until E3.7 is independently accepted.
- XFER1 remains `BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF`.
- production ECO authority remains inactive.
- production binding remains forbidden.
