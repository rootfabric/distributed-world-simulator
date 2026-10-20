# ECO ARCH2 A14.6 R1 — Fine A5 Latency & Allocation Decomposition

Status: PRODUCT CANDIDATE / NOT VERIFIED / NO MERGE.
Base main: ae9a669336d93b3497fa78e5bb6d8eb3a21a0211
(A14.5 R3 #781 merged and separately exact verified).
Branch: feature/eco-arch2-a14-6-r1-a5-latency-decomposition.

## Goal

After A14.5 R3, the LAB sim can suspend between PREPARE/ALLOCATE/ADVANCE
stages without publishing partial canonical biological state. A single A5
workset, global A4 Field.allocate_demands, checksum/cursor copy, admitted
reproduction and A6 feedback are still indivisible expensive operations.

R1 measures the real execution path and constructs a read-only conservative
resource dependency graph to guide a **separately reviewed R2**:
it does NOT break the canonical allocation barrier or add a second
resource allocator. ALL original A4/A5/A6/Runtime files remain unmodified.

## Read-only dependency/frontier graph

a5_allocation_frontier_probe_v1.gd:
- Validates the original A4 sealed Field and versioned Port demands, bound
  by A4 MAX_BATCH and a separate 131072-link diagnostic cap.
- Reproduces A4 cell-coverage geometry from request position/radius,
  retaining ascending row-major integer cell indices, including negative
  boundary clamping/floor division.
- Builds a bipartite demand–(cell,resource) membership graph; each resource
  bucket unions all touching requests into a stable conservative connected
  component, with source hashes anchored to the original field and the
  sorted canonical input demands.
- BOTH A4 passes must be considered. The second residual pro-rata pass
  traverses every requested cell/resource, even when the first-pass
  primary claim in that cell is zero. The conservative edge cannot be
  elided because a separate first-pass claim may fail at an empty cell.
- Returns only stable metadata (number of components, demands, resource
  buckets, primary-zero edges, max component, canonical component members,
  topology/hash). No grants, mutation, clocks, allocator invocation or
  partial canonical state. Graph components are NOT permitted to execute
  separately in R1.
- Unknown/duplicate/outside demands, stale/tampered A4 field, batch overflow
  and diagnostic link limit reject without mutating source.

Potential R2 partition criterion:
  separate components have disjoint (cell, resource) demand memberships
  through both pro-rata passes. However A4 still has a GLOBAL ledger,
  revision, integrity sealing, canonical grant ordering and A5 admission.
  Region/world ownership and cross-tick coupling are NOT separable merely
  because components are disconnected for one tick. R2 must produce a
  formal merge proof and byte-identical grants/field/ledger for any parallel
  or incremental candidate before enabling it.

## Fine wall-time profiler

a5_fine_latency_profiler_v1.gd:
- Runs on a supplied valid **actual canonical Runtime state**.
- Calls accepted Runtime.step_spatial_parallel_advance for continuous
  reference, and separately composes real A5 lifecycle, propagule
  admission and A6 feedback; requires identical final canonical bytes.
- Starts accepted Runtime.begin_staged_global_tick, then executes exact
  one-workset-at-a-time Runtime.resume_staged_global_tick across PREPARE,
  one global ALLOCATE, ADVANCE and final admission/feedback.
- Captures per-workset wall_us, member count/index, before/after
  canonically encoded cursor byte sizes, per-phase p50/p95/p99/peak/sum,
  measured begin, source validation, lifecycle, admission and A6 feedback,
  and max cursor memory footprint as diagnostic bytes.
- Captures ALL demands after PREPARE. Calls real A4 Field.allocate_demands
  once again on the detached starting Field and compares exact sealed
  global Field state and per-organism grant intake with the A5 ALLOCATE
  cursor before the first ADVANCE stage. This duplicate invocation is
  explicitly diagnostic and not an extra canonical allocation.
- Requires exactly one global A5 ALLOCATE on the canonical path, all
  PREPARE/ADVANCE worksets covered, no partial authoritative state,
  no source mutation, same final state/hash and A8 checkpoint bytes.
- Returns **only descriptive profile evidence**; never yields a second
  authoritative ecological state. Timings are noncanonical, not seeds,
  not scheduler decisions. The final ADVANCE stage includes final
  admission/feedback and sealing; breakdown separately profiles the
  reference lifecycle/admission/feedback calls for context.

## Test and provenance

validation/ecology/evo_arch2_a14_fine/test_allocation_frontier.gd:
  permutation invariance, disconnected components, same-cell competition,
  resource isolation, 1mg cross-cell demand with a ZERO primary link
  receiving a real A4 residual grant from a second cell, invalid input,
  duplicate requests, owner-write/conservation and source immutability.

validation/ecology/evo_arch2_a14_fine/test_fine_latency_profile.gd:
  accepted biological founder fixture at [4,32,96,256] (256 is the
  current R1 scale ceiling), exact per-workset phase coverage,
  global A4 field/grant parity, A5/A6 final bytes and A8 checkpoint,
  monotonic measured phases and no source mutation. Emits four machine-
  readable JSON lines for Windows/Linux evidence. No invented speedup
  or hard realtime p95 threshold. A single-sample p95 is diagnostic only.

## Acceptance / forbidden changes

- Portable Godot 4.7.1 cold import and both new falsifiers PASS.
- Self-hosted Linux + Windows Godot 4.7.1 double exact on identical HEAD/TREE,
  hashes bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
  and 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5.
- A14.5 R3 + R2 + R1, A14.4, A14.3, A14.2 and A13 regression exact.
- Project Control, clean tracked tree, fresh source review and independent
  verifier. Draft PR; no merge until exact evidence is complete.
- Do NOT weaken canonical A4 demand priority, residual pro-rata, global
  allocator/barrier, deterministic ordering, conservation, mutation receipt,
  A5/A6 biology or A8 checkpoint schema. No 256 limit increase.
- Do NOT claim R1 demonstrates hard frame latency or increases throughput;
  a full-world tick remains expensive. It only provides trustworthy
  diagnostics and a conservative topology for the next optimization.

## R2 next work order (NOT implemented here)

1. Profile decomposition bottlenecks by frame and process wall-time;
   add repeated cold/warm samples and process RSS/peak measurements.
2. Prototype **detached staged allocator preparation** with sorted stable
   demand buckets, explicit admission barrier, bounded cursor memory and
   cancellation. At all times one authoritative A4 grant/field result.
3. RED→GREEN adversarial first-/second-pass pro-rata/grant rounding,
   demand permutation, multiple cells/resources, field owner+revision,
   cross-tile competition, receipt-based reproduction, A6 feedback,
   failed mid-flight suspension, restart and exact checkpoint parity.
4. Only after R2 verifies safe allocator decomposition may A14.6 R3
   enable it in opt-in LAB staged frames. WORLD_COMPAT remains gated
   on separate Region/Matter transactional authority admission proof.
