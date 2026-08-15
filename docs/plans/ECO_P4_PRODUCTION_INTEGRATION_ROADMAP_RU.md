# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.6 ACCEPTED / P4.7 ISOLATED BOUNDED ROTATING CANONICAL RUNNER READY / P4.8 PREPARATION READY`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **ACCEPTED exact Windows full committed chain**.
6. P4.6 Interest + Client Read Model — **ACCEPTED exact Windows committed unit + real P4.5 integration**.
7. P4.7 Production Integration Soak — **ISOLATED BOUNDED ROTATING CANONICAL RUNNER READY; exact committed A/B pending**.
8. P4.8 P4 Acceptance — **PREPARATION READY; final acceptance blocked until P4.7 lifecycle acceptance**.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.5 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.6 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION.
P4.7 = CANDIDATE_BOUNDED_ROTATING_ISOLATED_HEADLESS_CANONICAL_RUNNER_EXACT_COMMITTED_A_B_PENDING.
P4.8 = PREPARATION_READY_P4_7_CANONICAL_SOAK_PENDING.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.
Accepted P4.5 aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.
Accepted P4.6 unit aggregate: `88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2`.
Accepted P4.6 real integration: `f8191c46658f345e54c85c61b29059939bbf9c7decda2892b9ef62e733a27bdf`.

Current P4.7 composition contract:

```text
8 authoritative regions
12 rotating cycles
8 real ecology generation steps
12 P4.4 persistence round-trips
12 P4.5 CAS commits
4 handoffs
3 restart reconstructions
12 client-cache updates
12 active-region interest projections
2 full eight-region fanout projections
fresh-process A/B byte-identical determinism
max catch-up debt <= 1
```

The original 96-full-region-operation soak reached the 600-second hard timeout twice because accepted lower-layer recursive validation/deep-copy/serialization was being replayed excessively. Timeout was not increased. The current bounded rotating design preserves the cross-layer composition surface while avoiding redundant replay of already-accepted P4.4/P4.5/P4.6 validation depth.

On exact Windows HEAD `6e7c6e47186ac5dbccb18ec17997d34f7cf06524`, the bounded scenario itself completed successfully with 242 assertions and provisional identities:

```text
soak_hash=d7cee96abd82c09afab50873bb07271d112684ccad3be4127a995ff8501cd2fe
final_interest_hash=62d28c383697a01c5b96ec6e9c72b3e71a8fbf5e51a76ddeccacae3885decd2e
```

They are not frozen acceptance evidence because fresh-process B did not run. The runner rejected A after unrelated project-level `BreakpointRuntimeBridge` UID autoload errors from the clean clone.

R9 isolates the headless ecology gate from repository gameplay/MCP startup configuration: a temporary minimal Godot project exposes the exact committed `scripts/` and `tests/` through NTFS junctions and contains no gameplay/MCP autoloads. The repository `project.godot` is not modified, production runtime is not changed, and unexpected Godot `ERROR:` output remains fail-closed.

P4.8 preparation is repinned to R9. It cannot accept P4.7 or P4 by implication. After exact isolated-project A/B PASS, freeze the two identities, accept P4.7, promote P4.8 final manifest, and only then write P4 lifecycle acceptance.

## Repository-local test workflow

Canonical local entrypoint:

```text
RUN_ECO_TEST_WORKFLOW.ps1
```

Standard current-frontier suite:

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite current -GodotPath $Godot
```

`current` executes P4.7 canonical soak and P4.8 fail-closed preparation. `accepted` runs P4.4-P4.6 regression gates; `full` runs P4.4-P4.8.

The entrypoint resolves repository root from its own file location and `git rev-parse --show-toplevel`; no ECO test contract depends on a fixed checkout path. If the source checkout has diverged from the remote ECO branch, `RUN_ECO_VALIDATION_WORKSPACE.ps1` uses a dedicated clean validation clone and leaves the source checkout untouched.

GitHub workflow `/.github/workflows/eco-production-tests.yml` invokes the same entrypoint on a Windows self-hosted runner with the exact double Godot. Detailed local/CI instructions are in `docs/control/ECO_TEST_WORKFLOW_RU.md`.
