# ECO ARCH2 A14.1 — Fidelity Performance Baseline R1

Status: RESEARCH / IN_PROGRESS. No performance claims yet.
Base main: `5460354b06f62cb48caa1c1e4f8156129ac5f9d4` (merged A13 PR #744).
Scope: measurement-only; no biological kernel, allocator, Runtime truth, checkpoint, or scheduling semantics change.

## Objective

Quantify CPU work, wall-clock time, peak process memory, replay burst cost, and spatial-plan validation overhead of the accepted A13 FULL / REDUCED / PATCH scheduler and bounded parallel prepare/advance. Distinguish **deferred** work from work actually saved; a REDUCED frame may defer exact replay but not eliminate its cost.

## Contracts

- Only existing A5 global resource allocation and existing A13 Parallel Advance can advance authoritative biology.
- FULL, REDUCED and PATCH remain exactly as accepted in A9/A13; PATCH due returns refinement-required without canonical mutation.
- Keep all instrumentation and schedule metadata outside authoritative Runtime/checkpoint.
- A measurement failure must not yield an ecological PASS or a claimed speedup.
- All comparisons use the same engine binary, seed, founder fixtures, tick interval, worker bounds, host, and process isolation.

## Experiment matrix

1. Initial *canonical* fixture sizes: 4 / 64 / 128 / 256 founders. A12 scale contract caps the current authoritative population at 256; 1024/4096 are NOT supported and must not be benchmarked as canonical throughput or bypassed by patching the scale contract inside the harness. Record requested larger configurations as OUT_OF_SCOPE / CAPACITY_LIMIT instead.
2. Serial baseline, Parallel Prepare (worker bounds 1/2/4/8), Parallel Advance (1/2/4/8), with a single A5 global allocator.
3. FULL cadence 1; REDUCED bounded defer + full catch-up at debt 1/4/16/64; PATCH due must fail closed and is measured separately as refusal overhead, never approximated as successful advancement.
4. Distinguish first-run/cold import from warmed measurements; record warm-up, iterations, median/p95/max and raw samples (no pooled cross-platform speedup).
5. Cost breakdown: spatial-plan construction, validate() full rebuild, prepare, global allocate barrier, per-workset advance, deterministic commit/merge, checkpoint serialization, wake replay.
6. Memory: process RSS/peak RSS or platform-native equivalent, allocations if reproducible; report unavailable metrics explicitly.
7. Capture wall-time and CPU-time separately when supported, plus worker utilization. Compare equivalent **committed simulation ticks**, not only user-facing scheduler calls.

## Scenarios and falsifiers

- Same deterministic initial population, seed and resource field across compared executors.
- Field/population/propagules/checkpoint hashes must match the canonical serial result for every exactly committed frontier.
- Repeated runs must yield identical canonical hashes, though durations may differ.
- REDUCED defer must not mutate canonical state; on wake replay exact debt; measure catch-up worst-case latency and 64-tick envelope.
- PATCH refinement-required must leave canonical state byte-identical.
- Invalid/stale plans, excessive worker bounds, replay failure, and stalled jobs must fail closed.
- Specifically quantify NOTE #3 from R2: `validate()` rebuild complexity vs population/workset size. Do not introduce caches before this baseline.
- Add a forced mid-replay failure after >=1 successful local replay step as a separate follow-up test (R2 NOTE #2), if the existing harness offers an isolation seam.

## Evidence and reporting

Produce a versioned, machine-readable JSON/CSV per run: exact PRODUCT_HEAD/TREE, main epoch, Godot version/SHA256, OS/CPU/RAM, fixture/seed, worker count, suite, cold/warm, durations/CPU/memory, authoritative hashes, exit codes and stderr.
Include reproducible Linux and Windows commands and SHA256 digests for result files.
Present distributions and the baseline-vs-A13 ratios with explicit uncertainty; identify replay spikes, scheduling overhead, allocator bottleneck and break-even size. Publish non-speedup verdict if the gains do not materialize.

## Exit gates

- Source scope and provenance verified.
- Linux exact regression A9/A11/A12/A13 PASS.
- Windows exact regression PASS or explicitly WAITING_HOST (not inferred).
- Profiling samples replayable and independently reviewable.
- Fresh independent performance-method review on frozen HEAD.
- No merge without separate human decision.

## Next steps

R1: locate existing test fixtures/runners and implement an external noncanonical profiling harness.
R2: capture Linux baseline with deterministic equivalence predicates.
R3: capture Windows exact baseline and cross-check parity.
R4: evaluate bottlenecks and propose separately reviewed bounded optimizations.

## R2 implementation progress (2026-10-10)

- Benchmark implementations: `bench_fidelity.gd` for executor parity and fidelity replay; `bench_scaling.gd` for canonical 4/64/128/256 founders with one-tick exact state hash equality.
- Evidence runner `run_benchmark.py` accepts only verified double Godot (SHA/version), executes three repeat samples of each suite by default, enforces all expected sample identities and checks scaling parity across 1/2/4/8 workers.
- CI `.github/workflows/eco-arch2-a14-1-performance.yml` adds official Godot parser smoke (not exact) and self-hosted Linux/Windows double exact.
- **CURRENT STATUS: SOURCE_PUBLISHED / EXECUTION_UNVERIFIED.** No exact PASS or speedup claim until the workflow jobs produce validated evidence. Host availability and benchmark performance remain unknown.
- Measurement limitations: GDScript memory monitor is a Godot internal metric, **not process RSS**; the runner currently measures wall time and stores execution samples. CPU-time, host RSS, warmup stratification and p95 aggregation remain R3 work.
- The initial 256-founder one-tick fixture must stay below canonical MAX_POPULATION throughout the test; otherwise report failure rather than truncating or silently increasing the cap.
