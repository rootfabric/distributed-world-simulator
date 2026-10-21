# EVO ARCH2 — Roadmap R7 / A14.6 R2 update

Статус: A14.6 R2 implementation candidate, NOT accepted until exact.
База: main 0a4f48d018e7eadfbb4df377b386be89062537f1.
R6 остаётся исторической архитектурной картой; R7 фиксирует
продолжение после A14.6 R1 (PR #788, MERGED).

## Train

| Этап | Контракт |
| --- | --- |
| A11/A12 | Persistent ecology; legal canonical scale 256 |
| A13 | Deterministic spatial/parallel/fidelity scheduling — accepted |
| A14.1–A14.4 | Performance/adaptive scheduling and live LAB budgeting |
| A14.5 R1–R3 | Resumable global tick, safe cursor, opt-in LAB — accepted |
| A14.6 R1 | Read-only fine latency profiler + resource dependency graph — accepted |
| **A14.6 R2** | **CURRENT: detached five-stage exact global A4 allocation proof** |
| A14.6 R3 | NEXT: performance and opt-in LAB integration if exact/benefit shown |
| A14.7 | NEXT: real frame-time, backlog, throughput and GUI soak |
| A15 | NEXT: guarded beyond-256 scale contract after memory evidence |
| A16 | NEXT: WORLD_COMPAT Matter/Region transaction and production acceptance |

## Non-negotiable global ecology coupling

A5 globally prepares EVERY organism demand; A4 Field.allocate_demands
performs a single globally ordered allocation with two pro-rata passes,
one shared ledger and field revision. No canonical tile commits
independently. First-pass zero claims can still couple requests in
SECOND residual pro-rata pass. A14.6 R2 can stage computation on a
detached source and return only a complete result after the ORIGINAL
A4 allocator independently proves exact field/grant equivalence.
A14.6 R2 is NOT production activated.

## R2 acceptance boundary

Windows/Linux double, portable, fresh independent verification, unchanged
A4/A5/A6/Runtime and canonical A8 checkpoint bytes; rounding/collision,
stale revisions, cancellation, memory cap, reproduction/feedback and
256-organism adversarial checks. A single expensive bucket/final seal/
original reference allocator remains monolithic, so R2 does NOT prove
a strict 30ms deadline or reduced total tick duration.

R3 must measure actual execution/memory and test source ownership
under cancellation/restoration before any LAB opt-in. Do not raise
population limits, add per-tile authorities or claim world-wide speedup
without measured exact evidence.
