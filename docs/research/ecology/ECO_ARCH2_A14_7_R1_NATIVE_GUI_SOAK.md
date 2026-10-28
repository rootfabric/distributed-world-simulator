# ECO ARCH2 A14.7 R1 — Real LAB GUI/GPU/Input Soak

**STATUS:** DRAFT EXPERIMENTAL / NATIVE GUI NOT VERIFIED / NO MERGE.

**Frozen direct parent:** [A14.6 R3.2.3 PR #821](https://github.com/rootfabric/distributed-world-simulator/pull/821) product `ea4af312941f47adf87f39bdca40cbd3cb9c60e0`, TREE `0b49adcceb414e32486f2e00d7ec341eee10948f`.
**Accepted main:** `aac301b9a9a89e027f6d99864437eb750a4202ca`. Do not modify or merge main/parents.
**Dependency status when started:** A14.6 R3.2.3 Product Portable/Linux Double SUCCESS; Windows exact queued, independent Portable SUCCESS, native independent queued. R1 cannot substitute their exact gates.

## Why R1

The accepted R3.2.3 portable benchmark showed one 256-organism frame ~9.4ms and max UI batch ~2.6ms. These were **headless**, not actual GPU frame-time statistics; the CPU worker still needs tens of seconds per tick. We require evidence from the real 3D scene, actual input, multi-tick backlog and device memory before calling the LAB smooth.

## Delivered architecture

1. Test-only `a147_scale_fixture.gd` reuses the R3.2.3 exact 4/32/96/256 canonical global field/population with the same seed and no mutations. The frozen source is injected into an actual LAB Controller **before** any lease. The experiment is NOT a production manifest with 256 founders.
2. `a147_gui_soak.gd` instantiates the real `eco_arch2_polygon_lab.tscn`, its Camera3D, P3 markers, P6 realizer geometry, Workbench UI and original canonical controller. It explicitly opts into R3 allocator + off-main R3.2.2 + staged presentation R3.2.3. Exactly one global resource owner, no partial grants/state, no biological formula or A8 checkpoint edits.
3. A test-only CameraInputDriver delivers deterministic mouse and W events via `Input.parse_input_event`/`Input.flush_buffered_events`. The actual scene receives events in `_input`; the LabCamera moves. Direct camera teleport is only used for initial framing, outside the measured sample.
4. Real `SceneTree.process_frame` intervals (NOT manually stepped synthetic `_process` or `--headless`) are saved per frame and summarized as nearest-rank p50/p95/p99/max wall time, >50ms jank frames, fraction <=25ms, scene draw calls and renderer/adapter/vendor. Also sample Godot static memory and external process-tree PeakWorkingSet/RSS, tick/backlog, background worker pending, projection debt, latency between committed canonical tick and visually published snapshot.
5. Exactly 2 requested canonical ticks and 120 post-commit rendered frames per population by default. At 256, the CPU worker may take tens of seconds; process limits scale from 65s (4) to 380s (256). Timeouts and leakage/canonical/source mismatch fail closed.
6. Screenshot is optional follow-up evidence; a headless, non-drawable or software-rendered window never counts as real hardware. Require active signed-in Windows desktop for Windows `--script` without `--headless`. Native Linux GUI is opt-in and requires physical display; no Xvfb masquerading as GPU.
7. A strict Python profile validator recomputes p50/p95/p99 from raw frame sample JSON and rejects all source/hash/window/input/marker/debt/evidence gaps; its negative tests reject fake headless and altered percentiles. The cold geometry/UI startup cost is measured and excluded from steady-state FPS distribution, not concealed.

## Test commands

Portable functional smoke **does not count as GUI evidence**:

```bash
godot --headless --editor --path . --import
godot --headless --path . --script res://validation/ecology/evo_arch2_a14_7/a147_gui_soak.gd -- --a147-preflight --a147-population 4
python3 validation/ecology/evo_arch2_a14_7/validate_gui_evidence.py --self-test
```

Windows PowerShell 7 interactive desktop (pinned Godot double wrapper SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`):

```powershell
pwsh -NoProfile -File validation/ecology/evo_arch2_a14_7/run_windows_gui.ps1 -Ticks 2
```

Archive `a147-evidence/` (per-size raw stdout/stderr, full raw frame JSON, signed/hex native exits, observed process-tree memory and runner identity) as GitHub Actions artifacts or durable external evidence. The Windows runner may be a background service with no interactive desktop; in that case the job MUST be reported as `GUI_BLOCKED`, not as a software fallback success.

Native Linux Double SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`; start `workflow_dispatch run_linux_gui=true` only if an actual X11/Wayland GPU desktop is available.

## Acceptance vs nonclaims

**Source gates:** Current tree and clean worktree; Portable preflight+negative-headless+validator self-test; Windows native 4/32/96/256 graphical full-frame evidence + strict Python validation; independent verifier of native input, no partial snapshots, hardware adapter; frozen R3.2.3 Windows/Linux exact and inherited A14.5–A13 regressions.

**Research targets to report** (NOT hard R1 success thresholds): GUI frame p99 near <=25ms and no >50ms spikes; render path draw-call counts; 2+ canonical ticks unchanged first-tick certified hash; bounded UI pending debt and memory; stable CPU worker lifetime and no task leaks. A slow tick may accumulate dozens of owed seconds even if the renderer remains smooth—report this explicitly and classify as `PERF_FINDING`. Single-run p99 cannot establish a multi-session SLA.

**Nonclaims:** not automatically 60 FPS, not proved GPU driver parity, not stable throughput, not scale >256, not new Biology/A4 authority, not WORLD_COMPAT/Earth activation. No merge before native exact + independent verifier + review. R1 measures real symptoms; R2 will fix the causally identified renderer/geometry costs and R3 will address tick throughput/debt.

## Native machine warning

Project defaults to GL Compatibility rendering. Pin console wrapper binary exactly; the Windows GUI binary may not be SHA pinned by existing project, therefore R1 runs the already pinned console build in graphical mode. Native RSS samples can be incomplete if Godot is wrapped or spawns child processes: report both Godot's memory monitor and process-tree observations, never use the shim's 3MB RSS as the renderer's usage.

No automatic force push or merge.
