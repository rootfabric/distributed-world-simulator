# PlanetSimulator agent development rules

## Language and delivery

- Project documentation and user-facing development reports are written in Russian.
- Code identifiers, operators, schemas, error codes and commit types are written in English.
- Every code delivery must include an archive containing only changed files with their original repository paths.
- Every code delivery must include exact Git commands for applying the work to the user's repository.

## Branch-first workflow

Before changing code, determine the current roadmap stage and name the working branch.

For a new roadmap stage or independently reviewable feature, create a short-lived branch from the current canonical `main`:

```bash
git switch main
git pull --ff-only
git switch -c feature/<stage>-<short-purpose>
```

Examples:

```text
feature/n1-transport-boundary
feature/n1-enet-snapshot
feature/n1-remote-item-command
feature/n1-reconnect-replay
feature/n2-process-harness
feature/r3.1-authoritative-recovery
feature/a0-distributed-runtime-architecture
feature/h0-listen-host-runtime
feature/a1-generic-aggregate-foundation
feature/s0-spatial-simulation-substrate
feature/t1-multi-peer-transport-v2
feature/b0-message-bus-contracts
feature/m0-aggregate-transactions
feature/s1-distributed-compute-contracts
feature/h1-playable-listen-host
feature/h2-host-client-ownership
feature/h3-dedicated-multiplayer
feature/a2-networked-gameplay-architecture
feature/m1-unified-networked-gameplay-core
feature/m2-dedicated-graphical-client
feature/m3-dedicated-graphical-multiplayer
feature/m4-canonical-shared-gameplay
feature/m5-graphical-multiplayer-acceptance
feature/m6-dedicated-recovery
feature/a3-single-server-multiplayer-architecture
feature/b1-nats-core-adapter
feature/n3-world-directory
feature/n4-authority-handoff
```

Do not create long-lived umbrella branches. A branch must close one checkpoint, contain its tests and be merged before starting the next major checkpoint.

## Fix workflow

A correction requested during review of code that has not yet been accepted stays on the same feature branch. Do not create another branch only for `fix1`, `fix2` or similar review iterations.

Use explicit fix commits:

```bash
git add <changed-files>
git commit -m "fix(<scope>): <specific correction>"
```

Create a separate fix branch only when the accepted checkpoint is already merged into `main`, or when the user explicitly requests an isolated hotfix:

```text
fix/n1-transport-boundary-lifecycle
hotfix/<short-critical-purpose>
```

## Required delivery instructions

Every response that delivers code must state:

1. Base checkpoint or base commit.
2. Recommended branch name.
3. Commands to create or switch to the branch.
4. Commands to unpack/apply the archive.
5. Recommended commit message.
6. Test commands.
7. Acceptance criteria.
8. Whether a review fix should remain on the same branch.

Never imply that the branch or commit was created in the user's repository unless it was actually published there.

## Commit naming

Use Conventional Commits:

```text
feat(network): add transport lifecycle boundary
fix(network): reject sends before ready state
test(network): cover transport queue overflow
docs(network): record N1 transport plan
refactor(items): isolate inventory presentation adapter
```

A checkpoint merge may use:

```text
merge(network): integrate N1 transport boundary checkpoint
```

## Quality gate

A task is complete only when it includes:

- implementation;
- negative and replay tests where applicable;
- focused test command;
- full relevant regression;
- updated roadmap/checkpoint documentation;
- machine-readable validation report;
- changed-file list;
- `git diff --check` result;
- archive with only changed files.

## Current roadmap checkpoint

```text
architecture base accepted: v16.9.4-architecture-a2-networked-gameplay
roadmap checkpoint accepted: v16.9.5-roadmap-single-server-multiplayer-first
runtime checkpoint accepted: v16.10.5-persistence-m6-dedicated-recovery (delivery fix1)
architecture checkpoint accepted: v16.10.6-architecture-a3-single-server-multiplayer (delivery review-fix1)
current playable validation candidate: v16.10.6.1-testing-m7-playable-networked-playground
architecture manifest: config/network/single-server-multiplayer-architecture.v1.json
playable validation manifest: config/network/playable-networked-playground.v1.json
strategy: FULL_SINGLE_SERVER_MULTIPLAYER_FIRST
next architecture stage after M7 validation: feature/b1-nats-core-adapter
```

Accepted foundation order:

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 → H1 → H2 → H3 → A2
```

Approved next order:

```text
M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

M1–M6 close A2-D01…D04. A3 freezes the complete single-server production path. B1 remains adapter-only and may begin only after A3 acceptance. N3–N6 remain blocked until A3 and B2. ENet is the graphical realtime transport; NATS must not create a second gameplay path.

Spatial identity never implies authority ownership. Cell/shard/address contracts may only be changed in an explicit versioned foundation checkpoint.

## MCP-driven Godot runtime control

Если задача требует запустить Godot, управлять запущенной игрой, проверить UI,
сделать игровой screenshot или прочитать runtime-логи, перед первым действием
полностью прочитайте `docs/MCP_GODOT.md` и соблюдайте описанный там контракт.

Критичные требования:

- использовать double x86_64 console Godot из `C:\Godot\godot\bin\`;
- запускать и завершать собственный процесс через MCP managed-process tools;
- передавать игровой ввод только через `runtime_inject_input`;
- получать изображение только через `runtime_screenshot`, не с рабочего стола;
- подтверждать эффект вводов состоянием, assertions, кадром и новыми логами;
- перед передачей управления человеку отпускать все удерживаемые actions.

## Current A3/M7 checkpoint

- Accepted runtime base: `v16.10.5-persistence-m6-dedicated-recovery`, delivery `fix1`.
- Accepted architecture: `v16.10.6-architecture-a3-single-server-multiplayer`, delivery `review-fix1`.
- Current playable validation candidate: `v16.10.6.1-testing-m7-playable-networked-playground`.
- Branch: `feature/m7-playable-networked-playground`.
- One `NetworkedGameplayService` remains the only production gameplay authority.
- LOOPBACK and ENet are adapters over the same canonical command/state path.
- Graphical clients are command producers and replica presenters, never authority owners.
- M7 graphical clients send `MOVEMENT_INTENT` only; canonical position, velocity and interaction origin are calculated by the dedicated server.
- M7 pickup/drop/place are spatially validated against authoritative player state; client transforms and client-authored `PLAYER_STATE` are rejected.
- M7 durable restore must detect `playable_sandbox` before Item Graph validation so the ten-slot Seven Days hotbar survives restart/reconnect.
- B1 may add only server-to-server messaging through existing ports; it must not replace ENet or fork gameplay.
- A3 focused runner: `RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1/.sh`.
- M7 focused runner: `RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.ps1/.sh`.
- M7 manual launch: `PLAY_M7_NETWORKED_PLAYGROUND.ps1/.sh`.
- Next architecture stage after M7 validation: B1 NATS Core adapter.

## Current NX1 deterministic network condition simulator

```text
accepted base: v16.10.8-network-nx0-observability-baseline
current checkpoint: v16.11.0-network-nx1-deterministic-condition-simulator
branch: feature/nx1-deterministic-network-condition-simulator
focused runner: RUN_NX1_DETERMINISTIC_NETWORK_CONDITION_TESTS.ps1/.sh
```

Every M3/M7 ENet peer must still complete `COMPATIBILITY_HELLO`/ACK before gameplay `JOIN`. Fingerprint mismatch must remain deterministic and must never create a player or mutate `NetworkedGameplayService`. Session binding is public `session-id/...` or a `sha256/...` digest, never a bearer credential.

Production transport composition is `NetworkTransportBoundaryV2 → NetworkConditionSimulatorPort → ENetMultiPeerTransportPort`. `LOCAL` must remain exact passthrough. Reliable application frames may be delayed as simulated retransmission but must never be intentionally deleted. Unreliable loss must use gap-tolerant latest-wins sequencing and suppress stale frames. Incoming sequence cursors must remain independent per delivery class and ENet channel group; an unreliable latest-wins cursor must never reject a valid reliable frame. Profiles are endpoint-local; applying the same profile on server and client compounds conditions.

Already queued frames must remain blocked during manual blackout and lag spike. This includes `MESSAGE_RECEIVED` events that have already moved into the simulator ready queue; lifecycle events (`PEER_CONNECTED`, `PEER_DISCONNECTED`, `TRANSPORT_ERROR` and listener lifecycle) must still bypass the block. Held message events must preserve FIFO order. New unreliable frames inside an active blackout are dropped; queued-before-blackout unreliable frames are retained until release. `disconnect_duration_ms` is a transport blackout, not a physical socket close. Physical restart/reconnect remains covered by M7 recovery. NX1 must not suppress movement results, batch snapshots, change ENet channel layout, introduce fixed-tick movement or alter persistence cadence. Those changes belong to NX2/NX3/NX9.

Product priority remains NX0–NX6 before B1 implementation.


## Current NX2 realtime traffic separation

```text
accepted base: v16.11.0-network-nx1-deterministic-condition-simulator / fix2
current checkpoint: v16.12.0-network-nx2-realtime-traffic-separation
branch: feature/nx2-realtime-traffic-separation
focused runner: RUN_NX2_REALTIME_TRAFFIC_SEPARATION_TESTS.ps1/.sh
```

Production channels are CONTROL=0 reliable, INPUT=1 application-sequenced unreliable, SNAPSHOT=2 application-sequenced unreliable, ITEM=3 reliable, RESYNC=4 reliable and TELEMETRY=5 application-sequenced unreliable. ENet must use raw unreliable for application-sequenced streams; stale/gap/latest-wins semantics belong to the boundary. Outbound queues remain partitioned per peer/delivery/channel stream. Reliable FIFO may never be replaced by realtime coalescing.

M7 clients send compact transition-based `PLAYER_INPUT_BATCH` frames no faster than 33 ms with at most three entries. Repeated idle samples must not displace an unacknowledged movement transition. The server must suppress every successful movement result, per-input delta and per-input full snapshot, while preserving reliable rejection. Compact authoritative snapshots publish no faster than 50 ms and acknowledge `last_input_sequence`.

Item commands remain on ITEM. Join/full Item Graph state and explicit mismatch recovery remain on RESYNC. M7 network persistence must suppress client `item.save` only through an explicit server-authoritative persistence capability; H1 listen-host save commands remain valid. NX2 does not claim fixed tick, prediction, remote interpolation buffer or async persistence. Those belong to NX3/NX4/NX5/NX9.

Physical ENet channel/mode validation is strict. A mismatched frame must be rejected using `PEER_LOCAL_QUARANTINE_V1`: disconnect and fail only the offending peer session, clear only its queues, keep the server boundary `LISTENING`, and preserve healthy peers. Never convert a peer-local protocol violation into a global boundary failure. Both NX2 focused runners must execute the physical two-client process regression and report `9/9`.


## Current NX3 fixed-tick authoritative simulation

```text
accepted base: v16.12.0-network-nx2-realtime-traffic-separation / fix2
current checkpoint: v16.13.0-network-nx3-fixed-tick-authoritative-simulation
branch: feature/nx3-fixed-tick-authoritative-simulation
focused runner: RUN_NX3_FIXED_TICK_AUTHORITATIVE_SIMULATION_TESTS.ps1/.sh
```

Production M7 movement messages only enqueue validated input state. Position and velocity may change only inside the 60-Hz server scheduler using exact delta `1/60`. Never reintroduce packet-arrival delta or client-provided `delta_seconds` as an authoritative movement budget. Each peer has an independent bounded input buffer with wrap-safe sequence window, stale eviction, jump-edge semantics and a 250-ms fail-safe hold.

Latest-wins INPUT coalescing requires `LAST_THREE_STATE_TRANSITIONS_FIXED_TICK_V1`: repeated state refreshes sequence without accumulating client time, while `idle → movement → idle` remains recoverable from a final batch. Movement snapshots remain compact at 20 Hz and acknowledge `last_input_sequence`. NX3 does not add prediction or remote interpolation; those belong to NX4/NX5.
