# ECO ARCH2 A14.5 R1 — Resumable Global Tick / A5 Barrier Proof

**Base:** A14.4 frozen product HEAD e826a3f9bea3f2a96a8a98979a65671e25fdd616 (PR #767, Draft).
**Branch:** feature/eco-arch2-a14-5-staged-global-tick-r1.
**Status:** experimental implementation; NOT VERIFIED, DO NOT MERGE.

## Purpose and boundary

A14.4 schedules only complete indivisible ticks and can exceed its CPU credit target.
This R1 creates a transient explicitly resumable A5 lifecycle:

1. **PREPARE** — bounded number of canonical spatial worksets; sampling and demands
   use existing A5 worker and demand helpers; resources/organisms are not changed.
2. **ALLOCATE** — one GLOBAL resource demand allocation for the entire population.
   This barrier is still indivisible, never region-by-region.
3. **ADVANCE** — bounded number of worksets, using existing A5 outcome helpers
   in canonical member order and preserving the global propagule cap.

After A5 completes, the Runtime bridge builds the same intermediate lifecycle
state and performs existing propagule admission and A6 feedback. Only a fully
sealed and validated whole tick is published. Any failure publishes no state.

## Source and cursor safety

- Begin requires a sealed, valid canonical Runtime source.
- Every resume checks the source state hash and immutable options hash.
- A5 checks a full field+population fingerprint and both cursor layers carry
  canonical SHA-256 digests against accidental modification. This is not
  authentication against malicious actors; cursors stay in a trusted host.
- The cursor holds transient, speculative data, NOT a valid A8 checkpoint.
  It can be discarded without modifying the canonical state.
- No member advances before the once-per-tick global allocation barrier.
- Historical A5 biology formulas, mutation receipt logic and A6 are unchanged.

## Falsifiers and acceptance

Dedicated test_staged_tick.gd at populations 4/32/96/256 tests:
- PREPARE → ALLOCATE → ADVANCE → COMPLETE across multiple resume calls;
- no 'state' in incomplete responses, and source bytes unchanged at every call;
- rejection of zero quota, stale source, changed options and tampered cursor;
- exact Runtime bytes, state hash and A8 checkpoint versus the accepted
  Runtime.step_spatial_parallel_advance at the same global tick frontier;
- a second consecutive staged tick remains exactly equivalent.
Portable Godot + Windows/Linux double exact and A14.4/A14.3/A14.2/A13
regression suites are required before any production integration.

## Explicit non-claims / remaining work

This is NOT a hard CPU deadline, nor is it wired into live LAB frames or
WORLD_COMPAT. Single workset, global allocator, admission, feedback,
integrity hashes and speculative state duplication may still exceed a
frame-time target. Per-resume hashing and copying must be profiled.
A14.5 R2 requires measured p95/p99 by phase, measured memory/cancellation
limits, and either bounded or resumable allocation/admission barriers.
Production input/world-authority isolation needs separate proof.
Do not merge until fresh independent review and exact gates are green.
