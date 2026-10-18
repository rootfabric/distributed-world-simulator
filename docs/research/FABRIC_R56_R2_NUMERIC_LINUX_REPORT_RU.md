# FABRIC R5.6.1 R2 — Narrow Numeric Conditioning Repair / Linux Exact

**Статус:** `IMPLEMENTER_LINUX_EXACT_PASS`, `READY_FOR_CANONICAL_WINDOWS_EXACT_AND_FRESH_INDEPENDENT_REVIEW`; **НЕ MERGE_READY**.

## Frozen identity

- PR: https://github.com/rootfabric/distributed-world-simulator/pull/784
- Feature: `research/fabric-r5-6-1-r2-dynamic-aggregates-r1`
- Product HEAD: `716cddeee0cb479bcf4d96496510c0be033f5e64`
- Product TREE: `8457feca07484eb9d4d7f0824af8dea962e66052`
- Parent original R2 RED: `2ea4debdcef7a38dc1de2a0acc9a906ccfcea442`
- Research base (R1 merge): `4f301fae461567362d408a51802cc3dde6730999`
- Canonical Linux Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Linux Godot SHA256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`
- Frozen exact source carrier: https://github.com/rootfabric/distributed-world-simulator/actions/runs/39110982417, artifact `12129954316`; source and full bundle SHA256 manifest PASS.
- New product HEAD reconstructed from carrier Git bundle in fresh detached clone, tracked-clean; HEAD/TREE/published parent checked; before == after.

## Independent RED bug reproduction

The old R2 index stores raw second moments about origin and subtracts center-of-mass terms. For two canonical 1 kg parts with local positions `(100000000,0,0)` and `(100000001,0,0)`, old published R2 returned **Iyy=0**, even though the independently centered sum is **0.5 kg m²**. The same false result occurs at an offset of 10^9. Original canonical ConstructionPartRecord accepts those finite coordinates, and old index reported a successful query (silent incorrect physics).

Original executable falsifier was run on exact old HEAD and is published on a separate GitHub review branch:
https://github.com/rootfabric/distributed-world-simulator/blob/review/fabric-r56-r2-numeric-cancellation-falsifier-r1/tests/research/fabric_bake0/review_r56_r2_large_offset_inertia_falsifier.gd

On the repaired index the identical falsifier is **GREEN**: for 1, 10^5, 10^7, 10^8 and 10^9 both principal moments equal 0.5.

## Narrow R2 repair

- Ten Fenwick moments are accumulated in a fixed **source-anchored frame**, first part's starting position. This removes a common position offset before calculating second moments; canonical center-of-mass is transformed back to source-local coordinates.
- Sparse owner-verified delta updates use the same fixed translated frame, maintaining O(k log N) *moment index update* (not end-to-end owner/graph cost).
- Six tensor components are checked against a conservative float64 roundoff estimator from the two Fenwick prefixes and center shift. When numerical uncertainty exceeds a declared engineering budget, `query_range` fails closed with `R56_R2_RANGE_NUMERIC_PRECISION_UNSAFE`; never publishes misleading finite inertia.
- This numeric guard is a *heuristic conservative envelope*, not a rigorous universal double-precision error proof. Origin changes remain frozen during a session; a far-offset narrow range may need explicit rebase/fallback in future work.
- 8 changed R2-only files; no R5.1–R5.5, R1, Construction, Matter, BRIDGE-4 or main edits.

## Canonical Linux exact on published HEAD (unmodified published runner)

| Gate | Result |
|---|---|
| Cold import, script parse | PASS |
| R2 acceptance | **3 × 626/0**, byte-identical payload |
| Scale 5k / 20k / 100k | **255/0** |
| New numeric conditioning | **54/0**; 5 large-offset cases, sparse update, ill-conditioned subset rejection |
| R5.6.1 R1 regression | **203/0** |
| R1 Narrow Admission | **26/0** |
| BRIDGE-4 canonical | **49/0** |
| Strict evidence collector schema v2 | PASS |
| Collector tamper matrix | **11/11** corrupted inputs rejected |
| Git identity before / after | MATCH |
| SHA256SUMS raw evidence | **17/17 PASS** |
| Runner | **EXIT 0** |

Deterministic result hash unchanged from R2 R1:
`7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43`.

## Validation gaps before merge

1. Canonical Windows exact on **new** HEAD/TREE, including numeric 54/0 and collector v2 + 11/11 tamper rejection.
2. Independent adversarial Reviewer: must independently inspect numeric envelope, test another update/order/tiny-span and fail-closed pathways (separate worktree/session).
3. Independent Verifier on frozen source, identical Windows/Linux result payload, replay original RED→GREEN unmodified and inspect SHA256 evidence.
4. Human permission to merge into the research branch only, not `main`.

**No merge performed; PR #784 remains DRAFT.**
