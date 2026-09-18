# FABRIC R4.1 — CURRENT-MAIN CONTROL AUDIT R1

```text
ROLE              = CONTROL_AUDIT
MAIN_BASE          = 99e8efe2422e02fedec40778e12748611d68fb5f
PRODUCT_BRANCH     = repair/fabric-r4-1-numeric-envelope-diagnostics-r1
PRODUCT_HEAD       = a5001eeafd012323548707d6b705b12301a91761
PRODUCT_TREE       = 934ecfed15bd0f18389a64daf44caee6748cd73e
PRODUCT_MUTATION   = NONE
CONTROL_GENERATION = 82
STATUS             = PENDING_REBIND_PC0
```

## Purpose

The historical FABRIC product lineage is intentionally based on the accepted R4 subject and carries an older main-owned control snapshot (registry generation 80). Running Project Control directly on that research lineage therefore projects stale directional-clearance state and can report RED independently of the FABRIC repair.

This control-only branch starts from current canonical `main` and adds only this audit note. It exists to answer a narrower question: **is the current main-owned Project Control plane itself non-RED while the frozen FABRIC R4.1 product remains isolated from main control files?**

## Product/control separation

The R4.1 product diff from historical accepted R4 is limited to:

- one R4.1 workflow and runner;
- research roadmap/repair notes;
- generalized FABRIC graph numeric code;
- COMPLEX2 PERF/CLOSE diagnostic code;
- research acceptance tests.

It does not edit `config/control/**`, branch passports, architecture ownership, directional-clearance registries, V0/NX runtime ownership paths, or canonical main control scripts.

Current main identities observed before this audit:

```text
main HEAD                         = 99e8efe2422e02fedec40778e12748611d68fb5f
project-program-registry generation = 82
directional-clearance blob          = 6fb05989406bd454ff21cffe8048d2793075b921
architecture-ownership blob         = 3319422747bd19bdef14abe5035fdd3c4af21d20
```

The product lineage's stale control snapshot is evidence of historical ancestry, not a reason to merge/rebase unrelated main control state into the R4.1 product subject.

## Decision rule

This audit is PASS only if the ordinary repository `Project Control` workflow succeeds on this current-main-derived doc-only PR.

A PASS does not review or verify the FABRIC runtime, does not freeze R4.1, does not authorize R4.2 reveal, and does not merge this PR. A product HEAD change makes this record stale for Director use.


## Exact current-main Project Control result

```text
EVIDENCE_CONTROL_HEAD = cd1a20316eb3d4e65a401309e443bcfa8938f32e
RUN                   = 35331685855
JOB                   = 105557226516
RESULT                = SUCCESS
ARTIFACT               = 10541561090
ARTIFACT_SHA256        = 9fb33d6401b30ad550da0aef1bc26f1ecdff8cb9029efd2718dcfccadfe54f01
```

All Project Control steps succeeded, including candidate consistency, architecture/ownership projection, complete Harness regression discovery, canonical-main PC0 auditor and directional-watch auditor.

Decision: `CURRENT_MAIN_PC0 = PASS` for product identity `5ed03392... / ef7366...`. This does not convert the historical product-branch PC0 RED into a PASS; it proves that the RED was caused by stale main-owned control bytes on that historical research lineage. This report-only commit requires one final status-head Project Control replay before Director may consume it.


## Subject rebind amendment

The prior PC0 executions remain valid evidence about the current-main control plane, but their product identity binding became stale when the product test-only helper commit moved the subject from `5ed03392...` to `a5001ee...`.

```text
NEW_PRODUCT_HEAD = a5001eeafd012323548707d6b705b12301a91761
NEW_PRODUCT_TREE = 934ecfed15bd0f18389a64daf44caee6748cd73e
PRODUCT_RUNTIME_CHANGE_SINCE_5ed = NONE
REQUIRED_NEXT = PROJECT_CONTROL_STATUS_REPLAY
```

No main-owned control file is copied into the product branch.
