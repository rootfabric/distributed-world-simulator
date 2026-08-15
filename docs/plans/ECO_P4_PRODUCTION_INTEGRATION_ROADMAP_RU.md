# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.7 ACCEPTED / P4.8 FINAL MANIFEST GATE READY`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **ACCEPTED exact Windows full committed chain**.
6. P4.6 Interest + Client Read Model — **ACCEPTED exact Windows committed unit + real P4.5 integration**.
7. P4.7 Production Integration Soak — **ACCEPTED exact Windows isolated headless fresh-process A/B**.
8. P4.8 P4 Acceptance — **FINAL MANIFEST GATE READY**.

## Current lifecycle

```text
P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN
P4.5 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN
P4.6 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION
P4.7 = ACCEPTED_EXACT_WINDOWS_ISOLATED_HEADLESS_BOUNDED_ROTATING_A_B
P4.8 = FINAL_MANIFEST_GATE_READY_P4_7_ACCEPTED
```

Accepted identities already frozen:

```text
P4.4 aggregate        = 4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2
P4.5 aggregate        = c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419
P4.6 unit aggregate   = 88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2
P4.6 real integration = f8191c46658f345e54c85c61b29059939bbf9c7decda2892b9ef62e733a27bdf
P4.7 soak_hash        = d7cee96abd82c09afab50873bb07271d112684ccad3be4127a995ff8501cd2fe
P4.7 interest_hash    = 62d28c383697a01c5b96ec6e9c72b3e71a8fbf5e51a76ddeccacae3885decd2e
```

P4.7 exact tested HEAD:

```text
cb5f6c69bfb0299770e09d3acff41a8fbf8aa61c
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

P4.7 accepted composition contract:

```text
8 authoritative regions
12 rotating cycles
8 real ecology generation steps
12 P4.4 persistence round-trips
12 P4.5 CAS commits
4 handoffs
3 restart reconstructions
12 client-cache updates
14 interest projections total
2 full eight-region fanout projections
fresh-process A/B logs byte-identical
max remaining catch-up debt = 0
242 assertions per process
```

The P4.7 runner uses a temporary minimal Godot project so unrelated gameplay/Breakpoint MCP autoloads cannot contaminate the ecology gate. `project.godot` and production runtime were not changed; unexpected Godot `ERROR:` still fails the gate.

P4.7 remains an accelerated deterministic bounded integration soak, **not** a wall-clock production-duration soak.

## P4.8 final gate

`RUN_ECO_P4_8_PREACCEPTANCE_TESTS.ps1` retains its legacy filename but is now the final manifest gate. It does not rerun P4.7. It verifies exact accepted validation blobs P4.1-P4.7, exact P4.7 test/runner identities, tested HEAD/Godot, frozen hashes, byte-identical A/B evidence and all exact counts.

Expected success marker:

```text
ECO.P4.8 FINAL GATES: PASS
```

After that single control-only gate passes, write the final P4 lifecycle acceptance checkpoint and mark P4 complete.

## Repository-local workflow

Canonical local entrypoint:

```text
RUN_ECO_TEST_WORKFLOW.ps1
```

For the next action only, use:

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite p4.8
```

`p4.8` does not require Godot and does not rerun the accepted P4.7 soak. If the source checkout diverged from remote, `RUN_ECO_VALIDATION_WORKSPACE.ps1 -Suite p4.8` runs the gate in the dedicated clean validation clone.
