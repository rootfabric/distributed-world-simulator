# NET-SMOOTH1 R4.2 — R3C.3 R0: staged Earth surface for non-blocking client attach

**Artifact type:** Implementation Work Order / preimplementation architecture, NOT product runtime code or acceptance.  
**Stacked base:** NET-SMOOTH1 R3C.2 semantic-tick repair PR #770, exact HEAD 811eef1bb8937ace068eb0e0b925b03c3a00e982.  
**Inherited R3C.2 parent:** PR #769, exact HEAD 381250bf2dfa4ead6ca586e60d90772af21c490c.  
**Authority:** Existing M3, NX3, NX4, NX5 and M6. No changes to canonical game state, server checkpoint schema, ownership, replay, checksum, FIFO or ACK-after-durable-commit.  
**Human merge gate:** ALWAYS closed at R0. This branch is a separate planning artifact.

## 1. Evidence and actual call graph

The latest independent Windows R3C.2 R2 report establishes:

- Exact Windows Godot double runtime 20/20 suites, 7268 assertions PASS; both independent process-kill windows PASS; M6 max reported main-thread persistence 40.7ms in that run.
- Three original canaries encountered PERSISTENCE_FATAL; separate repair PR #770 covers the same-revision ownership.server_tick projection and trace-worker String(int) fault.
- After narrow repair, one full canary has fully paired 24/24 ITEM durable windows with real receives, but its strict analyzer still rejects committed-view motion outside the pending window and 20Hz within-window spacing. This remains a FAIL, NOT a reason to weaken the analyzer.
- Client initial CONNECTED stall 3278ms, reconnect stall 3006ms. The report attributes these to synchronous earth_surface_rebuild: 13,825 terrain samples plus ~76k vegetation attempt upper bounds, NOT to the already-prewarmed Quaternius avatar.
- Full performance acceptance FAIL: ~57.1 server simulation Hz (minimum 59), ~205ms worst server gap (maximum 100), ~3054ms client-B worst gap (maximum 100), and growing replay export up to ~189ms in longer runs. Four-hour soak NOT RUN.

Source inspection at the PR #770 HEAD independently confirms the **synchronous Earth call graph**:

1. EarthApp._ready creates ProceduralEarthWorld and calls world.setup(logger).
2. ProceduralEarthWorld.setup builds the global mesh and calls prepare_surface_region(default_spawn, false).
3. EarthApp._ready later calls _spawn_explorer_at_canonical_spawn().
4. EarthExplorer.activate / teleport_to_body_surface calls earth_world.prepare_surface_region(direction, false) **again**, for the same default spawn. This can generate the local mesh and vegetation twice during client scene initialization.
5. EarthWorld.update_for_view also calls prepare_surface_region synchronously on a recenter threshold; teleports and distant region switches can reproduce the same stall after initial connect.
6. EarthWorld.prepare_surface_region synchronously samples the whole local mesh, builds normals, uploads ArrayMesh and invokes placement_system.regenerate. PlacementSystem samples terrain and creates MultiMesh instances in the same call; it clears old instances first.

Configuration-grounded work quantities (upper bound on placement attempts, not actual successful placements or measured times):

| Work | Exact source formula | Baseline |
|---|---|---:|
| Global geometry samples | (global_rings + 1) × (global_segments + 1) = 65 × 129 | 8,385 |
| Local geometry samples | 1 + local_rings × local_segments = 1 + 72 × 192 | 13,825 |
| Near + billboard tree attempts | (max_near_trees + max_billboard_trees) × 4 | 27,200 |
| Grass attempts | max_grass_instances × 3 | 42,000 |
| Rock attempts | max_rocks × 3 | 6,900 |
| Maximum placement attempts | Sum of above; some loops exit early | 76,100 |

Read configuration from config/planets/earth.json and config/generation/earth_vegetation.json, not hard-coded production constants. These formulas establish work scale, not speed or final vegetation population.

## 2. Release scope and explicit non-goals

**R3C.3 addresses only client Earth surface initialization / reconnect / recenter.** It may change ProceduralEarthWorld, EarthExplorer, EarthApp and presentation-only EarthPlacementSystem behind an opt-in client flag, with exact legacy code preserved when disabled.

- Proposed canary: DWS_NET_R3C3_STAGED_EARTH=1, honored ONLY for Earth game-client, and a corresponding GUI harness flag --r3c3-staged-earth.
- Do not change server M6 replay or durability and do not fix ~57Hz server time inside this branch.
- Do not remove/simplify rule sampling, reduce vegetation counts, turn off default collision/LOD presentation, silently drop biomes, substitute a procedural low-cost terrain, or hide an altered result behind checksum normalization.
- Godot SceneTree, MeshInstance3D, ArrayMesh.add_surface_from_arrays, MultiMeshInstance3D and GPU/RenderingServer mutation remain on the owning main thread.
- RefCounted rule instances/pipeline.sample, mutable RNG and generated transforms must NOT be shared concurrently with an ordinary live world; if a data-only worker is later proposed, require independently owned cloned rule state and a documented thread-safety test. The initial safe R3C.3 implementation is **time-sliced on the main thread**, not an unsound off-thread SceneTree shortcut.
- No "ready" network ACK is delayed, fabricated or redefined by visual loading. Network authoritative pose, floating origin and client movement continue independently of visual terrain readiness.
- Baseline connection pause is not considered solved merely because the pause moved from CONNECTED to launch startup.

## 3. R3C.3 phased implementation sequence

### R1 — deterministic scratch surface job and client route

1. Implement a pure-data, bounded per-frame EarthSurfaceBuildJob with generation token, immutable requested direction, planet radius, rule/config revision, seed, scratch arrays, statistics and deterministic progress cursor. The job holds no Node/Mesh/GPU handles, no attached gameplay authority and no peer/session identities.
2. Factor legacy _build_global_mesh and _build_local_mesh sampling/triangulation into shared deterministic ordered sample/triangle steps. With the same seed/config/direction, serial legacy and staged paths must yield the **same vertex/index/normal/color/UV arrays, exact sample counts, same biome counts and geometric statistics**. Elapsed wall-time fields are diagnostics only; do NOT normalize gameplay vectors/checksum.
3. Stop doing the complete local mesh and vegetation synchronously in client opt-in setup. World setup prepares the scene shell and starts a scratch job; EarthExplorer activation and recenter request a target generation, not a synchronous prepare_surface_region. Preserve exact legacy synchronous path when opt-in off or world is non-client.
4. The first visible global surface must also be staged or proven independently below frame budget: old setup synchronously calls _build_global_mesh (8,385 samples). Do not move a 3s stall from local to global build.
5. Process a bounded number of samples/triangles per frame, with an observed elapsed-microsecond budget (proposed initial target 2ms/slice, tunable after Windows measurement). Do not promise hard frame deadlines from a cooperative sample budget: one sample, one final ArrayMesh upload or driver call might still exceed budget. Instrument maximum individual-step time and fail GATE B if it does.
6. A requested new region increments a monotonic **visual job token**. Earlier results must be discarded before publishing to the scene, even if the job completed after the request. A canonical player pose is never rolled back to the visual job's old anchor.
7. Keep the previous complete region visible until a new region is ready. On a first launch with no region, keep an explicitly reportable loading/LOD state; never show incomplete old-region geometry as if it were the new region.

### R2 — exact deterministic vegetation preparation and bounded commit

1. Refactor PlacementSystem.regenerate into a staged data-preparation state machine with the **same RandomNumberGenerator seed, RNG call order, weighted choices and early-break conditions** as the synchronous path. For each candidate, retain the exact order of calls for trees, grass, rocks. Do not reroll on frame boundaries.
2. Keep transform buckets as scratch CPU value data. Advance the original candidate loops with bounded attempts per frame and controlled sample budget.
3. Build candidate MultiMesh/ArrayMesh resources and upload instance transforms in observable bounded batches on the **main thread**; measure actual upload stalls. Do not batch all 14k grass and trees into one expensive publish frame.
4. On completion, verify staged mesh/vegetation parity and epoch token; atomically replace the old visible presentation state and only then publish updated center_direction/east/north/anchor_world and earth_rebuilt. Do not call _clear_instances before new geometry is ready; hidden scratch candidates must not change authoritative collision or input state.
5. Cancel/deallocate abandoned scratch jobs and GPU candidates on teleport, recenter, world unload or changed rule/debug view; bounded memory and maximum one active + one replacement request. Fail visibly on build errors, never silently declare loaded with missing geometry.

### R3 — routing, telemetry, exact Windows acceptance

1. Route only the Earth game-client prewarm/reconnect/recenter path through the job. Preserve canonical Earth surface altitude and pose sampling (earth_world.get_surface_point), same camera/floating-origin basis and same Local/Remote Quaternius presentations.
2. Add stage traces: earth_build_request, earth_build_sample_slice, earth_build_normals_slice, earth_vegetation_slice, earth_mesh_upload_slice, earth_build_discard_stale, earth_build_commit, earth_build_cancel. Include job token, target direction fingerprint, rule revision, sampled/remaining counts, elapsed per-slice ms, cumulative ms, peak memory, and do NOT log entire mesh/players or private state.
3. Measure both the first Earth _ready and first CONNECTED transition and the subsequent reconnect separately, not just warmed-up frame metrics. Report visible world readiness latency separately from frame freeze.
4. Execute real Windows pinned Godot double exact import/parse, deterministic parity and M3/NX4/NX5/M6 regression before GUI.

## 4. RED→GREEN falsifiers (mandatory)

For the baseline R3C.2+repair HEAD capture evidence that the synchronous source paths exist, then on R3C.3 produce GREEN under the same exact Godot binary and configuration.

- **Duplicated initial generation:** opt-in setup / EarthExplorer activation must not call synchronous prepare_surface_region more than zero times while establishing connection. Legacy non-opt-in must still produce its accepted result.
- **Exact geometry:** baseline vs staged compare all 13,825 local samples, all 8,385 global samples, vertex position, triangle winding/index arrays, normals, UV/color arrays, statistics and draw/material options. Compare exact packed arrays with the pinned Godot double; mismatches must report first differing index.
- **Exact vegetation:** same source seed, tree/grass/rock transform buckets and ordering; compare every MultiMesh transform and visibility by tier, instance counts, color/material flags. Treat RNG drift / rare-biome drift as FAIL.
- **Lifecycle:** request region A, immediately request B, then teleport C. Only the latest token may become visible; no old region flashes after C, and the old completed region remains safely visible during rebuild.
- **Two-client continuity:** while client B builds terrain, client A still sees B move with valid NX5 tick/epoch, and reconnect does not create a second avatar or stale ownership. No server-authoritative state is mutated by visual jobs.
- **Stop/unload:** destroy Earth while a job is in flight, then reload. No stale callback to freed nodes, orphan Mesh/Thread, or unbounded memory.
- **Debug and reload:** debug_view changes, rule reload, LOD tier transitions and recenter all regenerate the correct revision; prewarmed mesh must not be published for an old rule revision.
- **Performance:** report connect and reconnect p99/p99.9/max frame gap; no main-frame spike beyond established <=100ms maximum and <=25ms p99, <=50ms p99.9. Maintain two-client network continuity and >=20Hz measured ITEM-pending movement. Visible-world completion time tracked separately.

## 5. Remaining R3 blockers not automatically closed by R3C.3

- Server simulation ~57.1Hz versus required >=59Hz; server loop max gap ~205ms versus <=100ms; replay export can reach ~189ms. File a **separate server replay-export budget/ownership Work Order**; do not weaken M6 atomic generation or move live service objects to worker threads.
- Committed-view frames reported outside pending ITEM windows and unexpected tick spacing in repaired canary. Require full raw trace reconstruction, operation/generation identity, proper warmup/full-trace pairing and a negative falsifier. **Do not change the 20Hz requirement or simply suppress these checks.**
- Control-plane Project Control on these stacked PRs is red and may involve separate historical control/harness baseline; investigate separately, not by bypassing control checks in R3C.3.
- Both process-kill M6 tests previously PASS in the independent report but must be rerun on the exact final integration HEAD after client/server changes. No 4h soak and no merge until all short gates prove acceptance.

## 6. Review gates, evidence and progression

- R0 DESIGN_READY: this document + machine-readable source audit, no production code.
- R1 IMPLEMENTED_CANDIDATE: opt-in deterministic geometry scratch, parity RED→GREEN, cold import and focused Godot exact.
- R2 IMPLEMENTED_CANDIDATE: bounded exact vegetation and main-thread GPU staged uploads, restart/teleport/wrong-epoch falsifiers.
- R3 FRESH_WINDOWS_NARROW: 2 GUI baselines, 3 × 120s 1800ms slow-ITEM canaries, real Quaternius, pinned SHA and detailed reconnect/first-frame timing.
- R3 FULL_ACCEPTANCE: full previous gates, >=59Hz server, <=50ms main-thread persistence, <=100ms max server gap, 20Hz ITEM movement, client p99<=25ms/p99.9<=50ms/max<=100ms, zero checksum rejects/early ACK, both crash windows PASS.
- SOAK 4h only after all short gates PASS. NO MERGE, no force push, no change to main.

Required evidence includes original HEAD/TREE, engine SHA, configuration and seed fingerprints, stage-by-stage JSONL with END and zero dropped records, geometry/vegetation parity checksums, first CONNECTED and reconnect walltime plus frame gaps, p99.9, exact per-actor receives, and independent verifier report. A budget is not equivalent to hard bounded execution until measured.

**R0 verdict: DESIGN_ONLY / GAMEPLAY_UNCHANGED / NO_PERFORMANCE_CLAIM / HUMAN_GATE_REQUIRED.**
