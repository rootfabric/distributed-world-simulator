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
current architecture candidate: v16.10.6-architecture-a3-single-server-multiplayer
architecture manifest: config/network/single-server-multiplayer-architecture.v1.json
strategy: FULL_SINGLE_SERVER_MULTIPLAYER_FIRST
next after acceptance: feature/b1-nats-core-adapter
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

## Current A3 checkpoint

- Accepted runtime base: `v16.10.5-persistence-m6-dedicated-recovery`, delivery `fix1`.
- Candidate: `v16.10.6-architecture-a3-single-server-multiplayer`.
- Branch: `feature/a3-single-server-multiplayer-architecture`.
- One `NetworkedGameplayService` remains the only production gameplay authority.
- LOOPBACK and ENet are adapters over the same canonical command/state path.
- Graphical clients are command producers and replica presenters, never authority owners.
- B1 may add only server-to-server messaging through existing ports; it must not replace ENet or fork gameplay.
- Focused runner: `RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1/.sh`.
- Next after acceptance: B1 NATS Core adapter.


## Parallel mutable-worlds simulation track

This track is independent from the accepted single-server multiplayer order and must not alter the production Moon runtime before its integration gates.

```text
architecture: Dynamic Matter Fabric
accepted: v17.6.0-simulation-mw6-matter-network-replication, delivery fix2
current candidate: v17.7.0-simulation-mw7-matter-interest-replication
branch: feature/mw7-matter-interest-replication
production worlds changed: false
world catalog changed: false
next after acceptance: MW8 regional persistence scaling, compaction and cross-server handoff preparation
fixture: body/asteroid-mw0, radius 1000 m, seed 2026073101
```

MW4 fix3 is accepted as a metadata-only correction over the functionally passing fix2 delivery: the verified focused topology is 187 assertions, not 103. Fix2 keeps the fix1 linear validated-access and bounded runner, and additionally enforces JSON-safe high-value energy budgets and laboratory receiver limits below `2^53`. MW4 adds authoritative session-local excavation over canonical MW2 snapshots: swept-capsule commands, revision fences, atomic multi-brick commit, exact replay, mass/energy/capacity accounting, extracted `MatterMaterialBatch`, continuous queries and selective MW3 presenter rebuilds. It must not alter Moon runtime, production world catalog, network authority or disk persistence. The Item Graph production adapter, deposition and compaction remain outside this checkpoint. Review fixes remain on `feature/mw4-matter-mutations` until acceptance.


MW5 fix7 is accepted and adds durable matter recovery for the isolated asteroid laboratory. Persistence bytes use `planet_simulator.matter_persistence_transport.v1`: every `TYPE_FLOAT` is encoded as exact IEEE-754 binary64 little-endian hex; contiguous float arrays use one length-delimited packed hex tag, while scalar and mixed-array floats use individual tags. Integer-valued floats such as `1.0` remain `TYPE_FLOAT`. The transport envelope has its own checksum; after exact decode the original typed DTO/checkpoint checksum is recomputed and compared. Untagged fractional JSON numbers are forbidden. Repository publication bytes must be exactly `MatterPersistenceCodec.encode_persistence_json(checkpoint).to_utf8_buffer()` with no terminal newline or normalization. Recovery must reject body/generator/grid incompatibility, ignore uncommitted pending files, fall back to a valid previous checkpoint when active is corrupted, repair that fallback as authoritative active, compensate unexpected component-restore failure, and serve exact replay without changing store/receiver/journal hashes. Process-level acceptance must not assume the capsule midpoint is vacuum: after commit it selects a deterministic positive-SDF lattice witness from changed snapshots, confirms it through the canonical continuous query, transports the witness position and pre-save SDF through exact binary64 encoding, and requires exact SDF equality after recovery in a fresh Godot process. Review fixes remain on `feature/mw5-matter-persistence` until acceptance.


MW6 adds single-server authority and replica synchronization for matter mutations without creating a second gameplay path. Commands must reuse `NetworkCommandEnvelope` and `NetworkCommandGateway`; replication must reuse `ReplicationEnvelope`. Float-bearing matter DTOs cross the wire only as `planet_simulator.matter_persistence_transport.v1` strings. The server alone executes `MatterExcavationService`; peer/session/actor bindings, authority epoch and brick revisions are mandatory fences. New committed and rejected journal outcomes advance one monotonic replication stream. Reconnect uses contiguous delta replay only when the base state hash matches, otherwise a full persistent-only snapshot is required. Procedural revision-0 bricks must never be replicated. Review fixes remain on `feature/mw6-matter-network-replication` until acceptance.


MW6 fix2 is accepted. The final matrix is MW6 `130/130 PASS`, M6 standalone `10/10 PASS`, M6 process recovery `128/128 PASS` and three consecutive full A3 PASS runs. The fix2 delivery is parse-only over fix1; the accepted semantics remain single-server matter authority, exact wire DTO, persistent-only replication, reconnect replay and snapshot fallback.


MW7 adds regional interest projections over the accepted global MW6 authority stream. Interest peers remain command-authorized by `MatterAuthoritativeServer` but do not receive its full sparse-store frames. `MatterInterestServer` filters committed persistent brick revisions into independent per-subscription regional sequences and projection hashes. Interest replacement is two-phase: the active view remains until a validated replacement snapshot atomically enters and evicts bricks. Reconnect uses regional replay or regional snapshot fallback. Procedural revision-0 bricks, global journal ownership, production Moon and world catalog remain unchanged. Review fixes must remain on `feature/mw7-matter-interest-replication` until acceptance.
