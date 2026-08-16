# ECO VIS2.2 — B R2 repair / C Observatory Panel candidate

Дата: 2026-08-17

Статус: **VIS2.2-A WINDOWS_RUNTIME_VALIDATED / VIS2.2-B R2 REPAIR CANDIDATE / VIS2.2-C IMPLEMENTED + ATTACHED-ENGINE FOCUSED PASS / FULL WINDOWS C GATE REQUIRED**

Не merge. Не self-accept. VIS2.2 целиком остаётся открытым.

## 1. Exact lineage

Repository:

`rootfabric/distributed-world-simulator`

Branch:

`feature/eco-vis2-2-replicated-causal-observatory`

Independently accepted VIS2.1-V base checkpoint:

`731f9d892e7747d391a79b88b24bae69769b3340`

VIS2.2-A exact Windows-validated candidate:

`950bcdaa2463f1604865aec8580b418c9eb5c1bc`

Initial VIS2.2-B AggregateModel candidate:

`b0398c6120eebc536b2b2589571f8f5ffd43ba2a`

Initial B Windows run correctly FAILED in the real PairSet integration because B consumed raw runner trace points instead of the canonical VIS2.1 trace-adapter boundary.

Canonical pair adapter was then introduced:

`scripts/labs/ecology/eco_vis2_2_pair_trace_adapter.gd`

The first R1 repair harness reached parser preflight but had a test-only helper omission:

`SCRIPT ERROR: Parse Error: Function "_fail()" not found in base self.`

This did not execute production simulation, AggregateModel or PairSet runtime and is classified as a non-production test defect.

Current B repair gate is superseded to:

`RUN_ECO_VIS2_2B_R2_TESTS.ps1`

with:

`tests/research/ecology/test_eco_vis2_2_aggregate_effect_model_r2.gd`

The R2 test defines the missing helper explicitly and retains the real canonical-boundary regression coverage.

## 2. Canonical B boundary

Accepted VIS2.1 does not treat raw runner trace points as authoritative comparator input. It derives canonical trace points from generation maps using:

`eco_vis2_1_trace_adapter.gd::from_generation_map()`

VIS2.2-B now follows the same boundary:

```text
PairSet generation maps
        -> VIS2.2 PairTraceAdapter
        -> VIS2.1 TraceAdapter.from_generation_map()
        -> canonical CONTROL/TREATMENT trace points
        -> VIS2.2 AggregateModel
```

The adapter also verifies per-replicate Control/Treatment root equality before emitting aggregate input.

At the fork generation Treatment is explicitly canonicalized as `BASELINE`; Treatment forcing remains effective only from fork+1.

## 3. VIS2.2-B R2 coverage

R2 keeps the original defect as a negative control: raw Treatment fork trace is expected not to be the canonical `TREATMENT` comparator point.

It then requires canonical fork input to prove:

- Control branch = CONTROL;
- Treatment branch = TREATMENT;
- fork Treatment experiment = BASELINE;
- equal fork field hashes;
- equal fork environment revisions;
- all replicate roots remain stable.

The real PairSet path then covers:

- canonical fork aggregate append;
- DROUGHT advancement to G36;
- post-fork aggregate effect;
- deterministic restart/replay;
- advancement to G50;
- cached rewind;
- Treatment-only FLOOD rebranch;
- changed future aggregate identity;
- unchanged Control future generation maps;
- unchanged replicate roots;
- unchanged canonical VIS2.0 source snapshot.

`RUN_ECO_VIS2_2B_R2_TESTS.ps1` first runs the already Windows-validated VIS2.2-A gate and preserves the strict ObjectDB/RID/resource/StringName shutdown-leak policy.

## 4. VIS2.2-C — Observatory Panel

Implemented new presentation-only files:

- `scripts/labs/ecology/eco_vis2_2_observatory_panel.gd`;
- `tests/research/ecology/test_eco_vis2_2_observatory_panel.gd`;
- `RUN_ECO_VIS2_2C_TESTS.ps1`.

The panel extends `Control` and owns no simulation state, PairSet, Control runner, Treatment runner, environment provider or renderer.

Input contract is only an already-computed VIS2.2-B bounded aggregate summary plus a selected replicate index.

Displayed information includes:

- fork and aggregate generation window;
- replicate count;
- selected replicate;
- aggregate series hash;
- Treatment experiment id;
- selected replicate population/fitness delta;
- aggregate population mean/median/range;
- aggregate fitness mean/median/range;
- positive/zero/negative effect counts;
- dominant/consensus direction;
- population and mean-fitness mean curves;
- min/max effect band;
- selected replicate effect curve.

Mouse input is ignored by the panel.

## 5. Critical C presentation invariant

Changing selected replicate is presentation-only:

```text
R0 -> R3 -> R1
```

may change only selected-replicate display fields.

It must not change:

- aggregate points;
- aggregate series hash;
- source caller dictionary;
- causal simulation state.

The panel deep-copies accepted input, returns deep copies to callers, rejects invalid selection without mutation and rejects malformed/unbounded aggregate summaries without replacing prior valid data.

It rejects aggregate histories larger than 64 points.

## 6. Attached exact-Godot focused evidence

Project-provided exact binary used locally:

`4.7.1.stable.double.custom_build.a13da4feb`

VIS2.2-B R2 parser-focused probe:

`PASS` — the previous missing `_fail()` parser defect is absent.

VIS2.2-C isolated panel parser:

`PASS`

VIS2.2-C headless panel runtime/draw probe:

`ECO.VIS2.2-C observatory panel: PASS (26 assertions)`

Strict output scan after shutdown found none of:

- `SCRIPT ERROR:`;
- `ERROR:`;
- `Parse Error`;
- ObjectDB leaked instance warnings;
- RID leak warnings;
- resource/cache still-in-use warnings;
- StringName leak diagnostics.

This attached-Linux exact-engine focused evidence is supplementary. It is not a replacement for the canonical Windows full branch gate.

## 7. Current acceptance runner

The authoritative next runner is:

`RUN_ECO_VIS2_2C_TESTS.ps1`

It performs:

1. exact Godot identity check;
2. strict shutdown matcher self-check;
3. full VIS2.2-B R2 gate;
4. therefore the full VIS2.2-A and accepted VIS2.1-V ancestry gates;
5. isolated C presentation project;
6. C parser preflight;
7. C headless draw/runtime smoke with `--verbose`;
8. zero-exit leak/error rejection;
9. explicit PASS marker enforcement.

The initial B runner and B R1 runner are superseded historical evidence and are not the current acceptance path.

## 8. Required next evidence

Run current branch HEAD with:

```powershell
.\RUN_ECO_VIS2_2C_TESTS.ps1 -GodotPath $Godot
```

Required terminal markers include:

```text
ECO.VIS2.2-A validated regression gate: PASS
ECO.VIS2.2-B R2 parser preflight: PASS
ECO.VIS2.2-B R2 canonical aggregate effect model: PASS (... assertions)
ECO.VIS2.2-B R2 automated gate: PASS
ECO.VIS2.2-B R2 validated regression gate: PASS
ECO.VIS2.2-C isolated presentation dependency graph: PASS
ECO.VIS2.2-C parser preflight: PASS
ECO.VIS2.2-C observatory panel: PASS (... assertions)
ECO.VIS2.2-C automated gate: PASS
```

Only after that should C be treated as Windows-runtime-validated and VIS2.2-D integrated-lab work begin.
