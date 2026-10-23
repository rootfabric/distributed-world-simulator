# ENGINE48_UBUNTU_REPORT — Godot 4.8 Beta 1 double on Ubuntu 22.04 (R1)

Date: 2026-10-21 (UTC) · Executor: local Ubuntu 22.04, x86_64, 12 scons jobs (~15 GiB RAM), rootless
Branch under test: `feature/engine48-beta1-double-migration-r1` @ exact `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9`

## PRODUCT_HEAD / TREE

| item | value |
|---|---|
| product HEAD (exact-HEAD worktree) | `a936412cc3d597a88fa789fc73c6ac7dcfd7a4e9` |
| tracked dirty files after all suites | 0 (`git status --porcelain --untracked-files=no` clean) |
| untracked (4.8-generated, deterministic) | 296 `*.uid` sidecars (documented migration adaptation) |
| repair branch | `repair/engine48-linux-runner-guards-r1` (own branch off migration HEAD, NOT the shared ENGINE48 branch) |

## BUILD

| item | value |
|---|---|
| source | `godot-4.8-beta1.tar.xz`, SHA256 `6d49c02e438935e49a12231d857b2b56131948b004d5b668bf295c9bc3b2281c` (verified before build) |
| upstream commit | `4d10419cacd6d3009976e8f9fd3abd970fd58018` (from tarball `.git`) |
| version string | `4.8.beta1.double.custom_build.4d10419ca` |
| targets | editor + template_debug + template_release, `precision=double arch=x86_64 GODOT_VERSION_STATUS=beta1` |
| install | `~/.local/opt/godot-double-4.8-beta1/` |
| binary SHA256 | editor `4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f`; template_debug `af1e29d1c53688786e0551c54b1d1105300955302180b02a7fdf5711d46ff897`; template_release `fffb8f53f85bda1757572638d88386e80f90a7e0abf1be61638544197f4506e7` (full table in `build/binary-sha256.txt`) |
| baseline build | local 4.7.1-stable double from source, `4.7.1.stable.double.custom_build.a13da4feb`, `~/.local/opt/godot-double-4.7.1-a13da4f/` (for paired A/B only) |
| build notes | scons 4.11.1 in venv + `zstandard` (required, else cert compressor exits 255); logs `build/{editor,template-debug,template-release,baseline-471-editor}-build.log` |

## IMPORT (cold)

- Cold import on exact HEAD: exit 0 (`cold-import.exit`), rewrites 13 `*.png.import` with 3 new 4.8 keys, generates 296 `*.uid`.
- Determinism: two independent imports produced byte-identical trees (`import-generated-import-updates.patch`).
- Accepted as migration adaptation; committed on repair branch (`231b3e9b2`).

## HEADLESS SUITES (4.8, exact HEAD content via repair branch runners)

PASS = exit 0 + no `SCRIPT ERROR:/Parse Error:/Compile Error:` + expected PASS summary.

| suite | result |
|---|---|
| 8-test Linux regression matrix (live2_enet_rollover, nx2_physical, live2_bridge, user1_slice, user1_seam, p4_reconnect, m6_recovery, mvp3_native) | all PASS (17/17 mvp3 native) |
| MW0 matter contracts | PASS (2011 assertions) |
| MW4 matter mutations | PASS (187 assertions) |
| MW10 cross-region (2 suites) | PASS (201 + 53 assertions) after stale-marker pin fix `7aaa7fa9e` (counts identical on 4.7.1 — pre-existing drift, strict check kept) |
| SM1 gates: L0, fault-matrix, graphical, authority-recovery, gateway-failure-restart | PASS (graphical after Xvfb override repairs `c1d3070fe`/`5f71900ff`) |
| P7.2 lunar matter bubble gate | GREEN |
| P7.3 material batch→Item Graph gate | GREEN (after stale P7.1 summary pin fix `841cf13e2`; counts identical on 4.7.1) |
| P7.4 persistence restart composition gate | GREEN (one load-induced timing flake `A observed dedicated crash` on a run executed while other gates ran concurrently; clean isolated rerun PASS 128/0 + MW6 130 assertions) |
| P7.5 two-client convergence gate | GREEN |
| V0 PLAYABLE SEAMLESS clients (all) | PASS |
| C22 compiled proxy scale/soak | PASS (75 assertions; compile_ms=3063, payloads=448, exact_parts=256) |
| MVP4 / MVP5 interactive harness | **FAIL — pre-existing Linux harness failure, identical on 4.7.1 (paired evidence in `worktrees/bench-471-mvp5`)**: gateway init `MVP3_BACKEND_DISCONNECTED`. NOT an engine regression. |
| MVP3 graphical | connects, peers see each other (7-8 both_visible snapshots); FAIL `MVP3_CANONICAL_COMMIT_NOT_PROVEN` — identical on 4.7.1 (paired) |

## NETWORK (live product path, real processes)

- M7 networked playground (`PLAY_M7_NETWORKED_PLAYGROUND.sh`, 4.8): server READY; 2 graphical gl_compatibility clients; profiles LOCAL and BAD_MOBILE; reconnect with no duplicate identity; M6 recovery; **server-restart mid-session with recovery/restore** — PASS. Artifacts `runtime/m7-network-playground/20261021-030410`, `…/20261021-030653` (+ `server-restart.json`).
- UX0 product launcher path (world=earth, `--product-seam`): launcher UI works end-to-end (see GUI), spawns correct server+client chains; **client session establishment fails with `M3_CLIENT_CONNECT_TIMEOUT` on BOTH 4.7.1 and 4.8** (paired direct-process reproduction: 4.7.1 server bound UDP 24590 in 30 s, launcher-exact client args → same timeout; 4.8 server bound UDP 24580, two client attempts → same timeout). Class matches the MVP4/MVP5 paired finding → **pre-existing Linux issue, not an engine regression**.
- NET-SMOOTH1 p99 ≤ 25 ms: **not directly measurable on this snapshot** (net_smooth1 instrumented branch not merged here). Paired watchdog/stall data below shows no regression of the class behind the Windows architecture finding.

## GUI (managed MCP runtime per `docs/MCP_GODOT.md`)

- Host `npx -y breakpoint-mcp`, runtime-only toolsets; managed run of the product on the guards worktree; bridge 9081; `godot_version` → `4.8.beta1.double.custom_build.4d10419ca`.
- `runtime_screenshot` (managed viewport, MCP-native): UX0 Product Shell renders and is interactive — main menu, Host World form (World=Earth, port 24580, persistence slot), status line «World запущен · server <pid> · client PID <pid> · slot world-01» after host. Screenshots `gui/mcp-main/runtime-screenshot-*.png`, `gui/mcp-world*/`, `gui/mcp-48-reconnect/`.
- World viewport of the spawned product client: sky/clouds/ocean/HUD captured via **targeted X11 window capture (xwd) of the game-client window** — the product architecture runs the world in a child process, outside the managed viewport; `window-client*.png`, `window-client-after-bind-*.png`. This is NOT desktop capture and NOT runtime_screenshot; mechanism documented here.
- HUD on captures: `Player: connecting · epoch 0`, `СВЯЗЬ: DISCONNECTED · M3_CLIENT_CONNECT_TIMEOUT` (consistent with NETWORK section).
- Rendering: OpenGL 4.5 Mesa **llvmpipe (software)** under rootless Xvfb `:99` (`XVFB_BIN` override). No hardware GPU is available to this executor.
- **GUI performance: INSUFFICIENT_EVIDENCE** for any real-GPU claim (software rendering only).

## PERF (paired, 3+3, alternating, identical scenario)

Server + client metrics, 180 s steady state, LOCAL profile; full tables in `perf/PERF_PAIRED_RESULTS.md`, parsed in `perf/perf-summary.json`.

| metric (mean of 3) | 4.8 beta1 | 4.7.1 stable | delta |
|---|---|---|---|
| worst server stage elapsed (cumulative watchdog max) | 686 ms | 743 ms | −7.7 % (4.8 better) |
| hard/soft stalls, rejections, script_errors | 0/0/0/0 | 0/0/0/0 | parity |
| cpu_seconds_total (3 procs) | 1446.4 | 1451.9 | parity |
| server RSS | 65.2 MB | 63.4 MB | +2.9 % (stable, no in-run growth) |
| client FPS p50 (llvmpipe-bound) | 16 | 16 | parity |

Caveats: watchdog `max_elapsed_ms` is cumulative-since-start; llvmpipe-bound FPS is engine-comparative only; box shared with another agent's acceptance run (load ~20-48) — paired design cancels this for A/B but absolute numbers are not referenceable.

## REGRESSIONS ATTRIBUTABLE TO 4.8

None found. Every failure observed on 4.8 was reproduced identically on the locally built 4.7.1 baseline (MVP4/MVP5 gateway, MVP3 canonical-commit, earth product-seam client session) or was an environment/timing flake (P7.4 under concurrent load). Stale exact-string pins in Linux runners (83→88 assertions; MW10 184→201, 51→53) were content drift present identically on 4.7.1 — repaired with strict checks preserved.

## REPAIRS (branch `repair/engine48-linux-runner-guards-r1`, off migration HEAD)

| commit | scope |
|---|---|
| `29d2e4af4` | 15 .sh runner guards: exact-string pin `4.7.1.stable.double.custom_build.a13da4feb` → `4.8.beta1.double.custom_build.4d10419ca` (strict checks kept) |
| `231b3e9b2` | 4.8 cold-import adaptation: 13 `*.png.import` + 296 `*.uid` |
| `24fc10ee1` | PINNED_ENGINES linux pin → 4.8 editor SHA (`EXACT_DOUBLE_ENGINE_REQUIRED`) |
| `c1d3070fe` | Xvfb location override (`XVFB_BIN`) in 3 .sh (rootless Xvfb support) |
| `5f71900ff` | `XVFB_BIN` in 13 .gd graphical gates (removes hardcoded `/usr/bin/Xvfb`) |
| `841cf13e2` | P7.3/P7.4 gate: stale P7.1 summary pin 83 → 88 assertions (verified identical on 4.7.1) |
| `7aaa7fa9e` | MW10 runner: stale suite markers 184 → 201, 51 → 53 (verified identical on 4.7.1; exit-1 on mismatch kept) |

Tree state after all suites: tracked-clean (`git status --porcelain --untracked-files=no` = 0 lines).

## VERDICTS

| area | verdict |
|---|---|
| BUILD + cold IMPORT | PASS |
| HEADLESS suites (matrix, MW, SM1, P7.x, seamless, C22) | PASS |
| NETWORK live (M7 playground incl. profiles, reconnect, server-restart) | PASS |
| NETWORK earth product-seam client session | FAIL — pre-existing on Linux (paired 4.7.1 = same), not a 4.8 regression |
| GUI rendering & interaction | PASS (software GL; interaction via MCP host verified) |
| GUI performance | INSUFFICIENT_EVIDENCE (no hardware GPU) |
| PERF paired 3+3 | NO 4.8 REGRESSION (worst-stage −7.7 %, rest parity) |
| NET-SMOOTH1 p99 ≤ 25 ms normative | INSUFFICIENT_EVIDENCE on this snapshot (instrumentation not merged); Windows ~39.8-41.3 ms finding remains open and separate |

## UBUNTU_VERDICT

**PASS** — for the ENGINE48 R1 scope runnable on Ubuntu: official 4.8-beta1 double builds and imports cleanly, all automatable headless/gate suites pass on exact-HEAD content, the live networked playground works including restart recovery, paired performance shows no regression, and GUI rendering/interaction is proven with managed MCP runtime evidence under software GL. Pre-existing Linux findings (MVP4/MVP5 harness gateway, earth product-seam client session) are confirmed engine-independent by paired 4.7.1 reproduction and are routed to the existing Linux-finding channel, not to ENGINE48.

This verdict is an executor-level factual report, NOT an acceptance declaration: canonical VERIFIED remains with the independent human verification flow.

## NEXT_ACTION

1. Publish `repair/engine48-linux-runner-guards-r1` (7 commits, tip `7aaa7fa9ebcabeeca33f15696002ff3907c22ffb`) and open a draft PR into `feature/engine48-beta1-double-migration-r1`; post this report as evidence on PR #794. **Push from this executor is GitHub-auth-blocked (403 on `git push`, `gh` not authenticated) → classified `EXTERNAL_TOOL_AUTH_REQUIRED`; durable fallback applied: `artifacts/engine48/linux/repair-branch.patch` (format-patch of all 7 commits, applies onto `a936412c`).**
2. Route the two pre-existing Linux findings (MVP harness gateway init; earth product-seam client session `M3_CLIENT_CONNECT_TIMEOUT`) with the paired 4.7.1 evidence to the Linux-issues channel.
3. Independent verification (real GPU + hardware GL, non-shared box) is required before any GUI/GPU performance claim; NET-SMOOTH1 p99 normative measurement needs the net_smooth1 instrumentation merged into this snapshot.

## Reproduction

See `artifacts/engine48/linux/reproduction.md` (binary paths, env, command lines for every suite, gates, M7, PERF, MCP GUI) and `source.json` / `build.json` for source/binary identity. Build/cold-import logs were produced in the exact-HEAD worktree (`worktrees/engine48-ubuntu/artifacts/engine48/linux/build/…`) and are consolidated here under `build/`; all suite/gate/M7/PERF/GUI artifacts were produced in this guards worktree.
