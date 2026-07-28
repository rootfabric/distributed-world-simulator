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
runtime checkpoint candidate: v16.8.0-runtime-h0-listen-host
architecture base: v16.7.1-architecture-a0-distributed-runtime
branch: feature/h0-listen-host-runtime
next implementation branch after acceptance: feature/a1-generic-aggregate-foundation
```

Foundation order is mandatory unless the roadmap checkpoint explicitly changes it:

```text
H0 → A1 → S0 → T1 → B0 → M0 → S1
```

Do not start World Directory, NATS adapters, Population Field runtime or distributed workers by bypassing these contract boundaries.
