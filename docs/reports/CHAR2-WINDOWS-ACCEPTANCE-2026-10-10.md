# CHAR2 Windows two-client acceptance — session report 2026-10-10

Session lead: verifier agent. Environment: Windows, RDP, 20 logical cores,
Godot 4.7.1.stable.double (bundled), CHAR2 HEAD `f861de654b5cc6aa281f150259bf55d4a42f042b`
(tree `3bf642cf75775cc041d9f2027be491c84b731515`), Earth world, dedicated
server + two GUI clients on 127.0.0.1:24580.

## What was done

1. Built the release ZIP from CHAR2 HEAD (`BUILD_CHAR1_WITH_AVATAR.ps1`):
   all strict verifications PASS (cold import, avatar-strict, body-visibility,
   char1-provider, char2-network-avatar, char2-product-camera).
2. Extracted to `C:\dwsv-char2-network-r1-run\CHAR1_REALISTIC_WITH_AVATAR`
   and ran dedicated server + clients A/B repeatedly (slots r1..r7).
3. Added run-time instrumentation to the extracted copy (NOT committed to the
   product code): per-2s client health (`char2_client_health.jsonl`), per-2s
   server health (`char2_server_health.jsonl`), avatar yaw diagnostic
   (`char2_yaw_debug.jsonl`), and `tools/CHAR2_NETWORK_WATCHDOG.ps1`
   (committed here).
4. Reproduced and root-caused three defects (see below). Collected evidence
   files under `C:\dwsv-char2-network-r1-run\`:
   - `monitor-r4-degraded.jsonl`, `monitor-r5.jsonl` — tick-rate timelines.
   - `health_before_restart.jsonl`, `server-health-r5-degraded.jsonl`,
     `client-health-r5-degraded.jsonl`, `server-health-r6-1500ms.jsonl` —
     degraded-session telemetry.
   - `r6-duration-growth.tsv` — server stage durations over time.
   - `network-watchdog.jsonl`, `network-watchdog-report.txt` — live watchdog.
   - `launch-two-clients.log`, `CHAR2-Release-build.log`.

## Confirmed working

- Two GUI clients see each other's real Quaternius avatar with animations.
- First/third person (V/F7): own body hidden in first person, remote stays
  visible; both visible in third person.
- Avatar facing accuracy: instrumented measurement of model forward vs
  bearing-to-observing-camera = -1.8°…-3.4° stable (within aiming tolerance).
  User confirmed: "смотрят прямо".

## Defect 1 (launcher): false UDP bind timeout

`START_TWO_CLIENTS_CHAR1.ps1` waits max 90 s for the server to bind UDP 24580;
after long uptime / cold start the bind happens later and the launcher aborts
(`CHAR2_SERVER_UDP_BIND_TIMEOUT`) while the server actually comes up. The
first attempt also left a duplicate unbound server process. Fix suggestion:
wait for `node_ready` + bind with a larger budget, or fail-fast on duplicate
process.

## Defect 2 (server, root-caused): synchronous checkpoint starves the tick loop

Symptom: after hours of uptime, movement lags, rubber-bands (prediction
rollbacks up to ~19 ticks / ~0.3 s), micro-freezes; eventually the server
stops accepting new connections (`M3_CLIENT_CONNECT_TIMEOUT`) while still
ticking. Measured on slots r3/r4/r5.

Root cause chain (all numbers from instrumented sessions):

- `M7_MOVEMENT_CHECKPOINT_INTERVAL_MS = 1500`: the dedicated server writes an
  M6 checkpoint synchronously inside `_process`.
- Checkpoint duration measured: 208–340 ms p50–p95 per commit (fresh state),
  growing linearly with state size.
- The checkpoint's `replay_state` grows without bound:
  `gameplay_replay.service_operation_ledger` (65 KB @ 3.5 h),
  `ownership_replay` (40 KB), `committed_outbox` (~3 KB per entry);
  whole file: 39 KB @ 15 min → 192 KB @ 3.5 h.
- Loop starvation drops the fixed tick rate: 59.5/s → 52 → 46 → 42 → 27/s
  over 3.5 h (see `monitor-r5.jsonl` timeline). At 27 Hz the 60 Hz fixed
  simulation runs under-speed → slow movement + prediction rollbacks.
- `transport_unreliable_sequence_gaps` grows ~1:1 with received messages
  (~19/s per client on a degraded server; systematic, not random loss —
  LOCAL condition profile is pure passthrough on loopback).

Palliative applied to the run copy (NOT committed): checkpoint interval
1500 → 10000 ms. Effect: persistence share of the loop reduced ~6.6×,
degradation pushed from ~2–3 h to roughly a day of uptime. User confirms
"стало лучше", but micro-freezes remain during movement.

Proper fix (needs a dedicated change in the NX3/M6 line, not CHAR2):
1. Bound `replay_state` (prune delivered `committed_outbox`, cap/rotate the
   operation ledger and ownership replay).
2. Move checkpointing off the main loop (async/incremental); 70–95 ms
   synchronous blocks every 10 s still steal ~1% of the loop and grow back.
3. Re-check the unreliable-sequence allocation on the server send path
   (gaps 1:1 with messages suggests two sequence streams are counted against
   one, or the sender skips sequence numbers).

## Defect 3 (avatar projection, user remark, NOT yet fixed)

"Когда один клиент поворачивается направо, другой видит, как будто он
повернулся налево" — i.e. the remote avatar's turning direction appears
mirrored on the other client. Suspects: sign convention between
`earth_explorer.get_surface_relative_yaw()` (atan2(f.x, -f.z)) and the
avatar consumption path (`facing = (sin yaw, 0, cos yaw)` in
`quaternius_avatar_adapter.gd`), or the delegate `rotation.y = yaw` frame.
The yaw instrumentation (`char2_yaw_debug.jsonl`, `signed_error_rad`) showed
only a small stable offset while both players face each other, so the mirror
likely appears during active turning (transient sign flip), which the static
measurement did not cover. Needs a turning-specific repro + fix; candidate
knob: `model_yaw_offset_deg` in `config/characters/production-avatar-catalog.v1.json`,
but a sign fix in the yaw chain is the correct target.

## User remarks / follow-ups (explicitly deferred by request)

- Mini-fix for the mirrored turning direction (Defect 3).
- Remaining network micro-freezes during movement: localize origin
  (client prediction replay bursts, NX5 interpolation underruns on sequence
  gaps, or render-side).
- Add technical logging for automated network-connection testing and
  automatic lag detection (the committed watchdog is the first step; the
  health instrumentation should be upstreamed behind a flag).

## Watchdog usage (committed)

`tools/CHAR2_NETWORK_WATCHDOG.ps1` watches the health JSONL files written by
the instrumented run, computes per-minute gap rates, snapshot tick lag,
snapshot age p95, prediction replay p99, rejections, and join failures, and
appends samples/alerts to `network-watchdog.jsonl` plus a human-readable
`network-watchdog-report.txt`. Thresholds are parameters; see file header.

Note: the run-time health instrumentation currently lives only in the
extracted test copy (`m3_graphical_client_runtime_nx6.gd`,
`m3_dedicated_server_runtime_p2.gd`, `quaternius_avatar_engine.gd`) and
writes to `user://char2_*_health.jsonl`. Upstreaming it behind a flag is a
recommended follow-up so automated soak tests can detect Defect 2 without a
manual rig.
