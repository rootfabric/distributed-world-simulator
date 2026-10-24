# ECO ARCH2 A14.7 R2 Stage E1 — A5 copy-on-write + granular validation cost (no bypass)

Status: EXPERIMENTAL DRAFT / NO MERGE. Exact direct parent R2D [PR #842](https://github.com/rootfabric/distributed-world-simulator/pull/842) at `1de21d1ac515c6806bdbb64fa100fb3d9976e0a4`, TREE `9c367065b7a55726720f277fbc9318e9c3676f54`. No main/parent PR changes. R2D Windows pinned product exact SUCCESS; independent Windows pending, Portable independent + ABBA SUCCESS.

## Why

Windows R1 genuine RTX 4060 GUI p99 6.3–7.3ms while n256 ecology canonical tick ~17.6s. Stage A found PREPARE 15.37%, global A4 ~25%, ADVANCE 32.78%, worker cursor encode 7.38%, plus repeated validation. Stage D Windows paired A4 only ~1152ms→939ms, full worker still many seconds. An unsafe skip of public `Runtime.validate` or A5 source digest can break nested-dictionary alias and restore/tamper safety.

Stage E1 **does NOT disable or memoize** any source/cursor/demand validation. Instead, exact phase-local COW removes redundant copying of read-only partial A5 cursors and measures the remaining repeated validations to determine if a guarded worker-owned fast admission merits separate E2 research.

## Implementation

- R3-only `resource_lifecycle_runtime_v1.gd::staged_resume`: keep COMPLETE signed cursor validation and source `C.digest({"field":source_field,"population":source_population})` before ANY result. The old A14.5/unstaged path performs original `cursor.duplicate(true)` unchanged. R3 ALLOCATE already shallow-COW. R3 PREPARE now clones only `samples` + `demands`; R3 ADVANCE clones only `next_population` + `propagules`. Other arrays are immutable input aliases and no mutated original cursor may emerge. A13 per-workset samples/outcomes are separately constructed; original single global A4 reference exact remains; no worker/biology/schema/ordering changes.
- Host-only optional `r2e_profile=false` trailing arguments to Lifecycle / Runtime / OffMain, frozen for entire OffMain job generation. Profile measures full Runtime source validation, option digest, A5 total, A5 cursor integrity check, A5 source digest, A5 COW deep-copy and A5 cursor seal. Counters attach ONLY to ephemeral CPU-worker telemetry on explicit opt-in, never to canonical state, A5/A4 cursor hash, grants, ledger, checkpoint or UI. Existing default-off paths and trusted Controller lease rules remain.
- Original R2D A5 script is copied byte-exact under test-only `a147_r2e_frozen_a5_reference.gd` for **actual frozen algorithm comparison**, not a reimplementation. Paired original vs R2E on exact n4/32/96/256 R1 canonical populations and same original A4; every PREPARE→one A4→ADVANCE resume checks full input-cursor deep immutability, phase/count equality, exact field, grants, all organism state/propagules compared to original A13 4x4; untrusted CPU worker with opt-in R2E profiling must reproduce exactly full original Runtime/A8 serialized bytes and frozen first-tick hash. Direct caller always executes **full last-minute Runtime.validate**. Reject changing profiling status while worker is in flight.
- Native Windows pinned Double SHA `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`, Portable official 4.7.1, cold import, 4 processes sizes n4/32/96/256, strict profiles/exit/no parse error; Project Control and inherited R2C/D/A13 needed; independent verifier to exercise stale/tampered nested input and deep cursor mutation across multiple PREPARE+ADVANCE calls.

## Evaluation

Report old vs new full A5 lifecycle wall and total OffMain per scale. Report fraction of total worker wall still spent on repeated Runtime source validate, A5 source digest, A5 cursor checksum, A5 copies/seals, options digest and A4 original reference. The breakdown overlaps: Runtime source validation and A5 are part of worker resume wall, and A5 nested metrics are subsets of A5 wall; do NOT sum all of them as independent percentages.

A single Portable or Windows sample cannot establish steady GUI p99 or native 10-minute tick backlog. Original target n256 <1 second is still distant; do not claim achieved without pinned Windows independent repeated complete worker samples and original canonical/A8 plus GPU soak/debt evidence.

**Merge gate remains closed.** E2 fast source admission would require an exclusively-owned deep-detached CPU worker frontier, no writable aliases, strict generation fences and full source/candidate final validation; public/direct/untrusted calls must retain their complete validations. Implement only after profiling and independent security review.
