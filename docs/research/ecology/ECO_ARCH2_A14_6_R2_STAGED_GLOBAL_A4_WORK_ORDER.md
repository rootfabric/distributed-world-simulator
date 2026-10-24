# ECO ARCH2 A14.6 R2 — Detached Resumable Global A4 Allocation

STATUS: DRAFT IMPLEMENTATION CANDIDATE / NOT VERIFIED / DO NOT MERGE.
BASE_MAIN: 0a4f48d018e7eadfbb4df377b386be89062537f1
(A14.6 R1 PR #788 accepted); product branch:
feature/eco-arch2-a14-6-r2-detached-staged-global-a4-r1.

## Goal / execution contract

A14.6 R1 proves a conservative demand↔(cell,resource) dependency
graph including zero-primary links in the accepted A4 secondary residual
pro-rata pass. R2 builds the first BOUNDED-ITEM decomposition of the
**whole global A4 allocator** on a detached host-owned cursor.

This is not per-tile allocation, not a second production truth, and NOT a
hard realtime slice guarantee. The original canonical A4 allocator remains
the only accepted resource owner, invoked once more at the final proof
barrier. A candidate may return complete state/grants ONLY if its
independently built result matches the accepted allocator byte-for-byte
on the original source. Its speculative cursor cannot be persisted as a
canonical A8 checkpoint or shared with untrusted peers.

## Five bounded stages

1. NORMALIZE: validate up to quota new demands per call against original
   Ports schema, enforce unique request IDs, compute exact A4 integer
   field coverage; sort all normalized demands by request ID at barrier
   (same order as A4).
2. BUILD_CLAIMS: create the canonical initial zero-grant records and
   split requests into positive primary claim buckets and FULL residual
   membership buckets. Zero primary amount edges are retained for the
   residual pass. Bucket sorting and construction may be a costly barrier.
3. PRIMARY: visit up to quota sorted (cell,resource) buckets per call;
   execute original integer target, per-request floor rounding and
   stable leftover distribution. Scratch field and partial grants remain
   inside transient cursor, not published.
4. RESIDUAL: visit up to quota sorted buckets per call including requests
   with zero primary claims; recompute remaining requests, fair proportional
   floor and deterministic leftover assignment exactly like original A4.
5. FINALIZE: set unmet amounts and revision/operation count, seal every
   cell and global field exactly as A4, validate Field conservation, then
   invoke the ORIGINAL Field.allocate_demands on the unchanged original
   field/demands once. Reject if ANY field bytes, grants bytes, revision,
   state hash differ. Only on full proof return one complete A4 result.

Every resume requires fully sealed/correct original Field, owner token,
owner epoch, revision, raw demands fingerprint and R2 cursor checksum.
The supplied cursor is immutable: resume deep-copies its owned scratch.
If invalid, corrupt, wrong owner, stale epoch, wrong quota or over the
configured encoded-memory cap, fail closed with NO state/grants or
substitute biological fallback. Host cancellation is simply dropping its
nonpersistent speculative cursor, then beginning from trusted source.

Proof-only API lives in
scripts/research/ecology/v2/a4_staged_global_allocator_probe_v1.gd.
There is no call from production Region/Matter ownership, EcologyWorkbench
or canonical Runtime. The R2 target is safe decomposition proof, NOT a
measured faster production allocator. Final baseline invocation remains
monolithic and O(N). Per-resume source validation/deep cursor hash/copy
and the entire one-item claim bucket may exceed any wall-time target.

## Security and conservation

Both passes consume the same global field, never independent regional
field state. Stable lexicographic request IDs order grants. The A4
per-cell resource ledger, revision and operation count remain global.
The R2 transient cursor checksum is integrity only, NOT untrusted actor
authentication. No changes to original A4/A5/A6/Runtime kernel and
no modification of canonical mutation/feedback/lineage/checkpoint data.

## Falsifier and exact matrix

- Primary integer rounding under competition, same-cell and different
  resource requests, cross-cell requests, zero-primary residual grant,
  demand reorder and different quotas => exact Field/grants/hashes.
- 256 canonical organism cap with 768 A4 demands; full cursor-cap and
  item quota bounds, strict source/cursor immutability and all five stages.
- Reject tampered cursor, obsolete schema, revised/alien owner field,
  changed demands, invalid source/duplicate request, zero quota, tiny
  memory cap. Abort after partial progress and start fresh => same grants.
- Actual A5 PREPARE calls produce demands, R2 reconstructs the A4 global
  field/grant result on detached input, and the original A5 ALLOCATE
  produces identical Field and per-organism intake; A5 ADVANCE+admission
  +A6 feedback exact to historical Parallel Advance and A8 checkpoint
  bytes at accepted scale [4,96,256].
- R1 read-only graph and fine profiler, A14.5 R1/R2/R3, A14.4,
  A14.3/A14.2 and A13 regressions MUST remain passing.
- Official Godot 4.7.1 portable smoke and exact Windows/Linux double,
  pinned Windows SHA256
  3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5,
  pinned Linux SHA256
  bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.
- Fresh separate source reviewer, independent verifier branch with
  frozen HEAD/TREE and production files unchanged, Project Control,
  clean worktree, no force push; merge only after every exact gate PASS.

## Following R3 — gated future work, NOT part of this change

R3 may compare candidate output with accepted A4 across randomized/frozen
golden vectors and produce measured cold/warm/RSS metrics. Only AFTER
independently verified byte-exactness and timing benefit can it begin
opt-in LAB staged runtime integration, with global A5 barrier ownership
and full-biology A8 checkpoint parity. No WORLD_COMPAT activation
without a separate owner/replay/transactional input contract.
