# FABRIC R4.1 — CURRENT-MAIN CONTROL AUDIT R1

```text
ROLE              = CONTROL_AUDIT
MAIN_BASE          = 99e8efe2422e02fedec40778e12748611d68fb5f
PRODUCT_BRANCH     = repair/fabric-r4-1-numeric-envelope-diagnostics-r1
PRODUCT_HEAD       = 5ed03392edcdaf0efaf743423f12bd9e1550e70a
PRODUCT_TREE       = ef7366f3452b812ab735c42d8447c3ca84c7bea3
PRODUCT_MUTATION   = NONE
CONTROL_GENERATION = 82
STATUS             = PENDING_PROJECT_CONTROL
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
