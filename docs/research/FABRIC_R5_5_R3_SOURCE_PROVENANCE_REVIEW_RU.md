# FABRIC R5.5 R3 — adversarial Reviewer: source provenance falsifier

**VERDICT: REVIEWER_FAIL_WITH_FALSIFIER (BLOCKER)** — not a separate-actor approval, not a product repair.

## Frozen identity
- PRODUCT_HEAD: `325e598665414a7ea8e7c5240c52d2029b113410`
- PRODUCT_TREE: `1b9e5936eb833c750a62aa311dbf021760cc280f`
- BASE_R5_4: `56ab06936b902e8c752be06eafa2e4d16465cc82`
- Godot 4.7.1.stable.double.custom_build.a13da4feb; canonical Linux SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

## New checks
1. New independent F1: coordinated runtime seal + `jxz[50020]` tamper **15/15 PASS**. Correct denial at UNBAKE, complete live structural/recursive rollback, clean retry exactly once. This is an independent second moment+endpoint from implementer's mass/50007.
2. New independent F2: alter mutable prepared-successor bond digest and coherently recompute both `spec.checksum` and mutable `_prepared_successor_hash`. The source preflight `Source.validate_subject(...,false)` and `Source.is_successor(...)` both returned success, and `local_damage_and_refine()` **committed**. Full recomputation of the committed source `Source.validate_subject(...,true)` returned **`COMPLEX3_BOND_DIGEST_MISMATCH`**.

## Strict RED reproduction

Run the added `tests/research/fabric_bake0/review_r55_successor_binding_falsifier.gd` against the **original frozen product** at the HEAD above, using the canonical Linux double Godot `--headless --path <project> --script res://tests/research/fabric_bake0/review_r55_successor_binding_falsifier.gd`.

RED payload: `checks=7`, `failures=["source digest tamper MUST be rejected before commit"]`, `event_success=true`, `rederived_error=COMPLEX3_BOND_DIGEST_MISMATCH`. This negative assertion is **expected to fail** on R3.

Canonical prepared successor full subject hash at initialization:
`30579f4208d5a033d3c6ad616702c44a271a6a4c1226d149ff05a325de7a7f3b`.
Canonical successor spec checksum:
`c6378b862ce376f9e32ad671701b10ce7ca5896d549fd6df21893f094bc633c3`.
Canonical expanded bond digest:
`c515ae265c9a236d428b2a0db9075b049596adfbd170b2ab94688274d9132080`.

## Root cause

R5.5 compares a mutable prepared successor payload with a **second mutable hash witness**. Coordinated mutation can make them agree. The underlying closed `Source.is_successor()` uses cheap validation without recomputing the 100k-bond digest. R3 code-anchored prefix seals do not pin the canonical full *successor* identity.

## Narrow repair handoff

**No edits to closed R5.1/R5.3/R5.4.** Pin the fixed-fixture full successor subject hash independently in R5.5 executable code, or an equally strong independent authoritative binding. On initialization and before any local staging, compare actual `U.canonical_hash(_prepared_successor)` and mutable witness against the immutable reference; do not rely solely on their equality to each other. Verify across Windows/Linux; keep event-path no O(N) bond rehash. Add RED→GREEN tests proving committed physical/source state unchanged on reject, recovery and exactly-once canonical commit.

This test uses mutable research runtime fields without editing executable source code. It does **not** claim an invisible hash collision: `machine_hash` changes after the invalid commit. The violation is admitting noncanonical structural provenance.

**Merge remains blocked; product PR #750 unchanged.**