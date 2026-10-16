# ECO ARCH2 A14.5 R2 — Stage Latency & Cursor Memory Optimization (R1)

**Base:** merged `main` `f369858c9bf7d6247785898537d7c8841b08b7bd` (A14.4 PR #767 + A14.5 R1 PR #768).
**Implementation branch:** `feature/eco-arch2-a14-5-r2-stage-latency-optimization`.
**Status:** implemented, NOT VERIFIED; PR must remain Draft until portable and independent Windows/Linux double exact are green.

## Motivation: measured regression

A14.4 Linux/Windows profiles demonstrate that the budget scheduler carries 1.5–3× wall-time overhead versus the continuous parallel baseline at 4/32/96/192/256 organisms. This R2 is a **narrow A14.5 staged-cursor optimization**; it does not yet claim to remove that whole A14.4 cost. R1's staged wrapper redundantly serialized the full nested cursor twice and deep-cloned it again at each resume. Runtime also called `state_hash` after `validate` (which validates again).

## Changes / proof boundaries

1. **A5 lifecycle cursor:** replace the redundant full deep clone in integrity verification with a *shallow top-level dictionary copy*, leaving every nested field read-only; compute the exact same R1 A5 checksum. Sealing receives a newly constructed/owned cursor from `staged_begin` or a detached `staged_resume` copy; mutate this owned dictionary in place instead of deep copying it again. The source argument remains immutable.
2. **Runtime wrapper:** version the nonpersistent host cursor from `dws.ecology.staged-global-tick.v1` to `v2`. Its checksum binds `{schema, source_hash, options_hash, lifecycle_checksum}`, instead of serializing the entire lifecycle payload again. This removes the redundant outer O(cursor-size) hash. The inner A5 checksum still covers **every** nested field and is verified *before any lifecycle stage advances*. The outer cursor constructor reuses an already detached A5 cursor, avoiding another duplicate.
3. **Validated source:** after `Runtime.validate(state)`, use the sealed `state.integrity_hash` directly for the source-frontier anchor instead of calling `Runtime.state_hash` and re-validating the full state. A5's own source fingerprint check is retained; no validation bypass is introduced.
4. **Versioned transient data:** old in-flight v1 cursors fail closed after hot code upgrade. This is permitted only because staged cursors were explicitly noncanonical/nonpersistent in A14.5 R1; clients must restart a speculative tick from their trusted canonical frontier.
5. **Zero biological change:** the global A5 allocation still runs once after all PREPARE work, propagation/admission and A6 feedback execute in canonical order, and the Runtime emits *only* a fully validated canonical tick.

## New acceptance falsifiers

`validation/ecology/evo_arch2_a14_staged/test_staged_r2_latency.gd` uses accepted fixtures at 4/32/96/192/256 organisms and checks:

- source state immutability on each suspension and detached repeatability;
- failed resume after changed options, moved source frontier, old cursor schema;
- **nested value tamper with unchanged nested checksum**: compact outer envelope passes its own checksum but A5 must reject the altered payload;
- altered inner checksum rejected by outer envelope;
- exact completed Runtime state bytes/hash/A8 checkpoint versus canonical Parallel Advance;
- exactly one global ALLOCATE call, bounded PREPARE/ADVANCE slices;
- per-phase p50/p95/p99/peak/call count, max cursor encoded bytes, and an apples-to-apples microbenchmark of full nested copy+hash against compact envelope hash.

The wall-time and memory measurements are *observations* emitted as JSONL artifacts, never canonical inputs or determinism gates. No speedup threshold is asserted until cross-host data exists. A14.5 R1 staged tests and A14.4/A14.3/A14.2/A13 regressions remain mandatory. Exact Linux and Windows use Godot 4.7.1 double and frozen engine hashes.

## Remaining risks / R2 next slice

- The A5 cursor still retains duplicate source field/population and retains one O(N) inner checksum + A5 source fingerprint on every resume. This R2 slice deliberately does not remove these trusted-source guards.
- Full `Runtime.validate`, source state copies, one expensive workset, the global allocator, A5 mutation admission and A6 feedback still contain indivisible work. **No hard wall-clock/CPU deadline** is guaranteed.
- Cursor checksum is *integrity*, **not authentication**; host holds it privately. No WORLD_COMPAT and no live LAB opt-in.
- Next R2 slice should profile/limit indivisible allocator and receipt/feedback costs, tighten cursor ownership, add independent golden vectors and a bounded-memory/cancellation falsifier before production activation.
- Final merge requires fresh independent source review, portable and Linux/Windows exact gates on same HEAD/TREE, no force push, no main changes.
