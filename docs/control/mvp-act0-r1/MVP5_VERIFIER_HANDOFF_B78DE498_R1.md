# MVP5 — FRESH VERIFIER HANDOFF — b78de498 R1

This branch is evidence-only. It MUST NOT become the product branch and MUST NOT authorize main merge.

## Frozen product subject

```text
branch = feature/v0-mvp-playable-seamless-planet-r1
HEAD   = b78de4980328bb7b4d19e030bb7f0fa5d9976cd8
TREE   = 0bfdd7595e10f007815bb666e62e7c5575172173
main   = 675c04bb213bbb68b8cdb500d540d57ce1490318
predicate = MVP_EXACTLY_ONCE_MATERIAL_OUTPUT
```

The product branch must still point to that exact HEAD before any verdict.

## Fresh exact Reviewer gate

Fresh Codex Reviewer on PR #597 completed on exact `b78de498` with no major issues.

- request comment: `5679618500`
- terminal result comment: `5679693047`
- reviewed commit: `b78de49803`
- result: `Didn't find any major issues.`

This is Reviewer evidence only. It is not a Verifier verdict.

## Exact MVP5 machine evidence

Workflow `MVP5 Exactly Once Material Output`:

```text
run      = 34964304441
job      = 104365023773
artifact = 10394302580
result   = SUCCESS
ZIP SHA256 = cb31317ba350b74c544704dc3741c362a7651b206eba5c662673254ff702746f
engine SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
manifest indexed members = 95
manifest mismatches after coordinator rehash = 0
tracked checkout after = clean
```

Raw exact results to consume independently from artifact `10394302580`:

```text
focused assertions = 270
focused failures = 0
failure-window cases = 4
native-accounting checks = 47
native negative corruptions = 10
five-process graphical = PASS
graphical failed_checks = []
visible terrain changed pixels = 372 / 372
minimum = 32
HUD-only false-positive controls = rejected
unchanged MVP4/MVP3 = PASS
```

Required semantic claims to verify from the raw evidence, not from this prose:

1. `LIVE_TOOL_GATED_DIG_TO_CANONICAL_OUTPUT`
2. `OUTPUT_EXACTLY_ONCE_UNDER_REPLAY`
3. `NO_SECOND_ITEM_IDENTITY_FOR_DUPLICATE_OPERATION`

Specifically check canonical mining-tool mint/equip -> equipped tool id in excavation request; one material item identity only; graph revision/tick advances once and replay advances zero; no second carve; before-apply recovery; lost-ACK recovery; late replay; replay-fingerprint conflict; foreign actor/session rejection; frozen source rejection; mass represented plus explicit residual.

The final graphical-race repair is bounded to `v0_mvp5_graphical_client.gd`: baseline capture now waits until BOTH authoritative players consumed stop input (`last_input_sequence >= 2`) and report zero velocity. The strict `static_capture_players` check and terrain/HUD thresholds were not weakened. The exact run proves all four `static_capture_players` checks PASS.

## Exact Project Control on the same product HEAD

```text
run      = 34964308428
job      = 104365037769
artifact = 10394392940
result   = SUCCESS
artifact ZIP SHA256 recomputed by coordinator = 2f74633e34290203fb288faae14682dc7b24d5aa840ea6335ebbc27f0b7037a4
full Harness = PASS
standard PC0 = YELLOW / non-RED
directional PC0 = YELLOW / non-RED
```

Standing YELLOW findings must remain visible; do not relabel them GREEN.

## Exact-product world/core

A separate read-only carrier exists only to execute world/core against the frozen product without moving the feature ref:

```text
carrier branch = control/v0-mvp5-worldcore-b78de498-r1
carrier HEAD   = dab6476ff0881de5a05a8fb49d14d781728083c2
workflow run   = 34967384187
product checked out by job = b78de4980328bb7b4d19e030bb7f0fa5d9976cd8
```

At creation of this handoff, the `exact-product-world-core` job is still running. A terminal evidence addendum MUST be committed to this carrier before a VERIFIER verdict. Do not infer PASS from an in-progress run.

Historical e3 world/core PASS is background only and must not substitute for the exact-product run if the exact-product run is available.

## Verifier responsibility

Fresh verifier context must be distinct from the Implementer and from the already-completed Reviewer. It may reuse trusted machine evidence because the Harness review policy explicitly allows an independent verifier to validate exact-head durable evidence without reexecuting every command; a separate cloud VM is not required by default. The Implementer cannot convert its own machine evidence into an independent verdict.

The verifier must live-check the product ref, retrieve/re-hash the referenced artifacts where possible, inspect the raw focused/native/graphical evidence, consume terminal exact-product world/core evidence, preserve every historical failure, and return one terminal verdict:

```text
VERIFIED | NOT_VERIFIED | FIX_REQUIRED
```

A `VERIFIED` verdict is leaf-only. Parent `V0-MVP-R1-WO-001` remains `IN_PROGRESS`; MVP6+ remain open; runtime/main merge are not authorized.
