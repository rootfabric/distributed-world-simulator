# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.6 ACCEPTED / P4.7 CANONICAL RUNNER READY AFTER TIMEOUT REPAIR / P4.8 PREPARATION READY`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **ACCEPTED exact Windows full committed chain**.
6. P4.6 Interest + Client Read Model — **ACCEPTED exact Windows committed unit + real P4.5 integration**.
7. P4.7 Production Integration Soak — **CANONICAL RUNNER READY AFTER TYPE+TIMEOUT REPAIR; exact committed A/B soak pending**.
8. P4.8 P4 Acceptance — **PREPARATION READY; final acceptance blocked until P4.7 lifecycle acceptance**.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.5 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.6 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION.
P4.7 = CANDIDATE_CANONICAL_RUNNER_READY_TIMEOUT_REPAIR_EXACT_COMMITTED_A_B_PENDING.
P4.8 = PREPARATION_READY_P4_7_CANONICAL_SOAK_PENDING.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.
Accepted P4.5 aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.
Accepted P4.6 unit aggregate: `88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2`.
Accepted P4.6 real integration: `f8191c46658f345e54c85c61b29059939bbf9c7decda2892b9ef62e733a27bdf`.

P4.7 canonical runner retains the legacy filename `RUN_ECO_P4_7_PREACCEPTANCE_TESTS.ps1` for compatibility. Its current contract pins accepted P4.6 and runs eight regions × twelve cycles with 32 handoffs, 96 production persistence round-trips, 96 client updates, 12 interest projections and catch-up debt no greater than 8. Forward and reverse processing order must converge to identical final identities, and fresh-process A/B logs must be byte-identical.

The first runnable version used ecology clock interval `1.0`; because every due generation descends into the full P3.8 `Coexistence.step`, the exact Windows soak A exceeded the 600-second hard timeout. The timeout was not increased. R6 keeps all 8×12 integration operations but changes only the soak clock interval to `10.0` and requires exactly eight real deep ecology generation steps per processing order — one per region. This bounds expensive research-model stepping without removing real ecology advancement from the production integration gate.

P4.8 preparation is already committed as a fail-closed control manifest and repinned to the R6 P4.7 surfaces. It cannot accept P4.7 or P4 by implication. After P4.7 PASS, only its frozen soak identities, lifecycle acceptance and one final manifest promotion remain.

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

The entrypoint resolves repository root from its own file location and `git rev-parse --show-toplevel`; no ECO test contract depends on a fixed checkout path. Current documented local checkout is `C:\distributed-world-simulator\distributed-world-simulator\`, but moving the checkout again must not require test changes.

If the source checkout has diverged from the remote ECO branch, `RUN_ECO_VALIDATION_WORKSPACE.ps1` uses a dedicated clean validation clone and leaves the source checkout untouched.

GitHub workflow `/.github/workflows/eco-production-tests.yml` invokes the same entrypoint on a Windows self-hosted runner with the exact double Godot. Detailed local/CI instructions are in `docs/control/ECO_TEST_WORKFLOW_RU.md`.
