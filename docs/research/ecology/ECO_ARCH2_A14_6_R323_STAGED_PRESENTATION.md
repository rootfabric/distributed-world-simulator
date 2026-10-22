# ECO ARCH2 A14.6 R3.2.3 — off-main exact snapshot + staged UI publication

Status: DRAFT candidate, main untouched, **NOT performance-accepted** until Linux/Windows double, full regressions, fresh independent verifier and observed GUI frame evidence.

Frozen parent: R3.2.2 PR #819 product `ee9daa930f7d9040b6330e737154ebb748df025c`, TREE `81771fc7f5c9beaa0556615b3fbaa82aa85eee8b`.
Accepted main: `aac301b9a9a89e027f6d99864437eb750a4202ca`, unchanged.
R3.2.2 portable 256 (one fixture): full final source admission in main only 0.005ms, **Workbench commit frame 1872.0ms**, pending frames 0.595ms. This means moving the final Runtime.validate into worker did NOT yet solve GUI freezes. No per-call attribution of exact UI subcomponents on 256 was available at R3.2.2.

## Research-only R3.2.3 scope

**Default OFF, LAB-only, requires explicit R3 + OffMain opt-in.** Existing A14.5/R3.1/R3.2/R3.2.2 default paths unchanged.

1. Pure CPU `ecology_r323_snapshot_projector_v1.gd` runs in the same immutable worker after the existing full source/candidate validation. It precomputes EXACT historical `Controller.get_snapshot()` DTO (per-organism life/development hashes, field/feedback hashes, lineage and presentation), but uses the already-validated candidate integrity hash instead of calling `Runtime.validate` a second time on the GUI. There are no Node/graphics calls in the worker.
2. The LAB Controller admits the finished source+candidate validation receipt using the accepted exclusive generation lease and atomically adopts ONE canonical tick. Only after adoption does it cache the worker's detached snapshot. Cache is noncanonical, not persisted, and invalidated by every supported owner mutation, cancel, PAUSE and restore. UI snapshot getters return detached data with the exact current tick/hash fence. Direct/untrusted OffMain path remains fully validated and does not admit a presentation cache.
3. Workbench adds an R3.2.3 opt-in. On completed canonical tick, use the verified cached snapshot, construct small descriptor views, and queue marker/morphology Node updates across subsequent frames. One batch contains at most 6 presentation items with a 12ms SOFT per-frame wall target. An indivisible giant organism mesh could still exceed it (no hard 30ms deadline claim).
4. If the UI is behind, canonical clock advancement is deferred until the current presentation finishes. A completed tick is NEVER rolled back by the UI, and pending frames emit no partial `snapshot_updated`. The canonical snapshot signal fires once when all presentation is complete. PAUSE/restore reconfiguration cancels stale UI cursors; any source tick/hash drift fails closed.
5. The existing historic `get_snapshot()`, morphology APIs and default UI paths are untouched. New UI fetches detached single-organism morphology slices, never a full `debug_state()` deep clone on the commit frame.

## Acceptance and falsifiers

- Native 4/32/96/256 use separate fresh Godot processes, including a test-only deep-detached, injected-before-lease population in a real Controller + Workbench `_process` (not a production 256-founder manifest).
- Test exact historical `get_snapshot()` canonical text parity against CPU projector, baseline Runtime byte/hash and A8 checkpoint parity; all 256 marker/morphology objects present and no speculative canonical grants/biological state.
- No repeated full synchronous snapshot, no deferred UI partial event, one task joined/committed, source unchanged, zero UI fallback. New frame metrics: `main_commit_process_wall_us`, `main_presentation_begin_peak_us`, `main_presentation_pump_peak_us`, `worker_projection_wall_us`, UI frame count. Gather native p50/p95/p99 from repeated GUI frames only, not single peaks.
- Fresh independent verifier must exercise cancellation during staged presentation, stale source/restore, exactly one signal and current source identity.
- All R3.2.2 R3/R2/R1, A14.5–A13 regressions and Project Control remain required.
- WORLD_COMPAT/Earth disallowed; no biological formulas/owner/RNG/checkpoint schema changed; do not merge without formal gate.

Current nonclaims: 30ms hard frame bound, complete morphology GPU upload latency, multiple-tick throughput improvement, 256 population user-facing UX, WORLD_COMPAT activation.
