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
architecture checkpoint accepted: v16.9.4-architecture-a2-networked-gameplay
roadmap checkpoint accepted: v16.9.5-roadmap-single-server-multiplayer-first
runtime checkpoint accepted: v16.10.1-runtime-m2-dedicated-graphical-client (ACCEPTED_WITH_GATES)
runtime checkpoint candidate: v16.10.2-runtime-m3-dedicated-graphical-multiplayer
strategy: FULL_SINGLE_SERVER_MULTIPLAYER_FIRST
next after acceptance: feature/m4-canonical-shared-gameplay
implementation manifest: config/network/dedicated-graphical-multiplayer.v1.json
```

Accepted foundation order:

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 → H1 → H2 → H3 → A2
```

Approved next order:

```text
M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

M1–M6 close A2-D01…D04. B1 remains adapter-only but is deferred until A3 acceptance. N3–N6 remain blocked until A3 and B2. ENet is the graphical realtime transport; NATS must not create a second gameplay path.

Spatial identity never implies authority ownership. Cell/shard/address contracts may only be changed in an explicit versioned foundation checkpoint.
