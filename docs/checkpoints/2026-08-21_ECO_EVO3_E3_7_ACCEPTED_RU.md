# ECO EVO3 E3.7 — ACCEPTED

Статус: `RESEARCH_ONLY`.

## Точная идентификация

- E3.7 PR: `#187`.
- Historical failed review HEAD: `97d01ec3cca450709af53a80c233970ee1187d62`, blocking finding `E3.7-R1-001` (HIGH/BLOCKING), durable verdict PR comment `#5369696271`.
- Repair R1 executable freeze: `b30f7a9cfb54a673c6249be1e5f9a3c7f60042c9`.
- reviewed/verified/accepted HEAD: `bdf9dd8bef6e4883cb30973550f5ce288c76b97a`.
- canonical E3.7 merge: `0a6b58ba276b2b84aca1aeeacfd4bfb382b3ba06` (= exact candidate `bdf9dd8bef6e4883cb30973550f5ce288c76b97a` composed into exact accepted base `c9f0b0becb3d2494097d946202788b9d1aa292f4`; parents exact, tree `8211c4f66610aa3abc734149a69f6ea78b3337a6` byte-identical to the pre-validated merge-ref `fbb8addb34b2809c5f90e55e003b5f3af41c3bfa`, which was validated by Project Control run `#1122` before acceptance; the realized merge sha differs from the predicted merge-ref only by GitHub's fresh committer timestamp).
- exact-head E3.7 Closure: `32481702894 / #10 — SUCCESS`, job `96769272444`, artifact `9446294053`, ZIP SHA-256 `5036de824d730fbebf41b1fc6b23a627bdaddee8075befdfe23666926420e8ad`.
- exact-head Project Control: `32481702988 / #1122 — SUCCESS`, job `96769272788`, artifact `9446291387`, ZIP SHA-256 `00c03c4e96de885472908e4effd0a18e447b3364b99464a9e8cf719232dd7872`.
- Normative Repair R1 Evidence Map: PR comment `#5369788752`.
- fresh independent Reviewer PASS: PR #187 comment `#5370213207`.
- fresh independent Verifier PASS: PR #187 comment `#5370307701`.
- Formal Acceptance decision (Director gate): PR #187 comment `#5370372420`.
- `E3.7-R1-001 = CLOSED`.

PR #187 was merged with exact expected-head protection: the merge ref `fbb8addb34b2809c5f90e55e003b5f3af41c3bfa` had been independently tested by Project Control before acceptance, and the canonical merge preserves the independently reviewed/verified candidate with no post-verification executable mutation (realized merge tree `8211c4f66610aa3abc734149a69f6ea78b3337a6` is byte-identical to the validated merge-ref tree).

## Accepted E3.7 PlanetEcologyProgram identity

```text
committed Git blob            01207a7025710db34fafc959fcc26dade2606d89
artifact bytes                104186
artifact SHA-256              52ff70fddc7f05fde00e5159f38dd8e67def3e732b03c93a15bedce540dae303
provenance hash               832a2d1c5b78ceda2f674843b4e6ee7052f5bd8a8400181aec7aeb029b472eff
planet ecology program hash   b405d35ebd8bebcc3218249fe78e495b94f4098eb06673eebc3e6475ea7a4956
tests                         30/30
closure predicates            16/16
authority regression tests    16
```

Accepted deterministic replay:

- regions `1`, species manifest entries `2`;
- active basis keys `22`, active spatial keys `11`, temporal envelopes `11`;
- individual entities `0`;
- seasonality state `UNRESOLVED_SINGLE_SNAPSHOT` (fail-closed, no invented disturbance history/schedule);
- authority `RESEARCH_DERIVED_NON_AUTHORITATIVE`, `canonical_binding_resolved=false`, `production_binding_authorized=false`.

The accepted authority boundary requires exact retained raw bytes for the E3.7 contract + binding + exact accepted E3.1–E3.6 chain + persisted EVO2 SpeciesCatalog. Parsed/reconstructed JSON does not acquire serialization authority. The historical generic final-byte helper `serialized_bytes(v: Any)` was removed in Repair R1; final serialization exists only through capability-bound `serialize_planet_ecology_program(...)` / `write_planet_ecology_program(...)`, each of which reparses exact raw inputs, independently rebuilds the program and requires canonical byte equality before emitting.

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

No RED value is renamed or reinterpreted as GREEN/NON_RED. This bounded research acceptance does not authorize production ECO, XFER1, canonical foundation/species/time/environment ownership, persistence, network or transaction authority.

## Frontier

`ECO.EVO3/E3.7 = ACCEPTED`.

`ECO.EVO3/E3.8 = BLOCKED` pending the post-merge accepted ECO control state. E3.8 may be authorized only by that resulting control state through a separate dispatch.

XFER1 remains `BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF`. Production ECO authority remains inactive. Production binding remains forbidden.
