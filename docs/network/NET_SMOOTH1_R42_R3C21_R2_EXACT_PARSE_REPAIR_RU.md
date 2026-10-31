# NET-SMOOTH1 R4.2 R3C.3 R2.1 — R2 narrow native parser repair

## Frozen ancestry and scope
- Direct parent: PR #777, exact `fd108cf698bba6be6b316bdb8b603f788f7b48b0`; stacked parent PR #775 `1645bba8af775fb989717b8a556f7431ca347dc4`.
- Branch: `repair/net-smooth1-r42-r3c21-r2-exact-parse-r1` (no force, no merge); `main` and both parent feature branches remain untouched.
- Exclusive edit in Godot source: **test-only** `anchor_before` in `tests/runtime/test_net_smooth1_r42_r3c21_frame_paced_visual.gd`. Production Earth, M6, ItemGraph, network, avatar, protocol, authority and legacy path are unchanged.

## Exact RED evidence, already observed
- [Windows job](https://github.com/rootfabric/distributed-world-simulator/actions/runs/38876465037/job/116892602400): pinned Godot `4.7.1.stable.double.custom_build.a13da4feb`, failure before first assertion of the new R2.1 scene test at line 131: `Cannot infer the type of "anchor_before" variable because the value doesn't have a set type.`
- [Linux job](https://github.com/rootfabric/distributed-world-simulator/actions/runs/38876465037/job/116892602558): same parser failure at the same line; not a Windows-only GPU issue.
- Source contracts 37/37 PASS on original PR #777 do **not** supersede the above native red.
- Project Control separately reports `CANDIDATE_MAIN_DRIFT`: its candidate local observation `3d7672c...` differs from canonical `main f369858c9bf7d6247785898537d7c8841b08b7bd`. This is a provenance/registry human review blocker, not evidence of a GDScript or renderer failure.

## Narrow repair
- Declare `var anchor_before: Vector3 = candidate.surface_anchor_world` explicitly. The member is declared as `Vector3` in EarthWorld but `candidate` is dynamically constructed, so GDScript cannot infer the RHS type for `:=`.
- Add source regression requiring this explicit annotation. Keep the native hidden-forest/collision/cancel/geometry parity falsifiers unchanged; they must execute on actual Godot.
- Run the existing exact workflow for the child repair branch, with a per-ref concurrency key so one stacked branch does not cancel the other branch's checks.

## Required native validation (no waivers)
1. Fresh SHA and ancestor check: tested HEAD == child branch HEAD, parent `fd108cf698bba6be6b316bdb8b603f788f7b48b0` is ancestor. No tracked modifications.
2. Windows 4.7.1 double executable SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`; Linux double executable SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
3. Cold import + `--script res://tests/runtime/test_net_smooth1_r42_r3c21_frame_paced_visual.gd` + all retained R2/R1/M6/CHAR suites in `.github/workflows/net-smooth-r42-r3c3-r21-client-frame-exact.yml`.
4. **Fail closed** for parse errors, test assertion failures, nonzero process exit and OS timeout. Publish complete logs, HEAD/TREE and per-file checksums. If a new issue appears, report exact root cause and repair in another narrow step, not a skipped test.
5. Fresh independent reviewer must verify that production Earth, gameplay authority, durable-before-ACK, snapshot checksums and default-off R2 path are unchanged.

## Windows GUI acceptance after exact PASS (separate gate)
Use a logged-in Windows GUI desktop, not a headless/service session. Frozen candidate and R2-only baseline must run **on the same machine, renderer, resolution and profile**, real server plus two genuine Earth+Quaternius game clients. Fresh worktrees:
```powershell
$Repo = 'C:\distributed-world-simulator'
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
git -C $Repo fetch origin
git -C $Repo worktree add 'C:\dws-r3c21-r2-baseline' 1645bba8af775fb989717b8a556f7431ca347dc4
git -C $Repo worktree add 'C:\dws-r3c21-r2-parse-repair' origin/repair/net-smooth1-r42-r3c21-r2-exact-parse-r1
# Within EACH worktree run its own cold Godot import first, then:
python tools/net_smooth1/run_net_smooth1.py --godot $Godot --mode gui --scenario local --duration 120 --warmup 20 --r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased --r3c3-staged-earth --output artifacts/net-smooth1/r3c21-r2-only
# In candidate, use different output and add:
#   --r3c21-frame-paced-presentation --output artifacts/net-smooth1/r3c21-r2-repaired
python tools/net_smooth1/analyze_net_smooth1.py artifacts/net-smooth1/r3c21-r2-repaired
python tools/net_smooth1/analyze_r3c21_visual_frames.py artifacts/net-smooth1/r3c21-r2-repaired
```
Run three **candidate** `--scenario r3-slow-item --slow-item-writer-ms 1800` canaries (one fresh output per run), including reconnect, plus the inherited M6 replay/recovery gates. Preserve artifacts from every run. Do not infer performance PASS from a headless test, from source contracts, or from the diagnostic-only analyzer.

**Acceptance thresholds:** per-client frame p99 <=25 ms, p99.9 <=50 ms, max frame gap <=100 ms; server tick >=59 Hz; 0 invalid checksums / silent ACK-before-durable / lost replay / PERSISTENCE_FATAL. Use `analyze_net_smooth1.py` as the normative verdict and preserve 120 s client traces with END, 0 loss and frame attribution across visual swaps/reconnect. If any is exceeded, FAIL/WITH_FINDINGS and perform a cause-specific repair; do not merge.

## Human gates
PR #777, PR #775, this repair and original R1 stack remain DRAFT until exact native + GUI + independent review and Project Control provenance are resolved. No direct `main` merge, no 4h soak and no performance acceptance before evidence.
