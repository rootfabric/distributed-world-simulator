# ECO P4 — Production Ecology Integration Roadmap

Статус: `P4.1-P4.8 ACCEPTED ON BRANCH / P4 BRANCH LIFECYCLE EVIDENCE COMPLETE / MAIN PROMOTION PENDING`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **ACCEPTED exact Windows full committed chain**.
6. P4.6 Interest + Client Read Model — **ACCEPTED exact Windows committed unit + real P4.5 integration**.
7. P4.7 Production Integration Soak — **ACCEPTED exact Windows isolated headless fresh-process A/B**.
8. P4.8 Final P4 Acceptance Manifest — **ACCEPTED exact Windows control-only final manifest gate**.

## Branch lifecycle result

```text
P4.1 = ACCEPTED
P4.2 = ACCEPTED
P4.3 = ACCEPTED
P4.4 = ACCEPTED
P4.5 = ACCEPTED
P4.6 = ACCEPTED
P4.7 = ACCEPTED_EXACT_WINDOWS_ISOLATED_HEADLESS_BOUNDED_ROTATING_A_B
P4.8 = ACCEPTED_EXACT_WINDOWS_FINAL_MANIFEST_GATE
P4 branch lifecycle evidence = COMPLETE
```

Final lifecycle evidence:

```text
validation/ecology/eco-p4-production-integration-acceptance.json
blob = fa0c1b3540f1efe1a8509a7551542e12fb353bcd
manifest_hash = 02d8804eb102e45eea5999744e09d4b159c22439798415b7637d0cce66596b06
```

Checkpoint:

```text
docs/checkpoints/ECO_P4_PRODUCTION_INTEGRATION_BRANCH_LIFECYCLE_COMPLETE_RU.md
```

## Frozen runtime evidence

P4.7 exact tested HEAD:

```text
cb5f6c69bfb0299770e09d3acff41a8fbf8aa61c
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Frozen identities:

```text
P4.4 aggregate        = 4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2
P4.5 aggregate        = c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419
P4.6 unit aggregate   = 88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2
P4.6 real integration = f8191c46658f345e54c85c61b29059939bbf9c7decda2892b9ef62e733a27bdf
P4.7 soak_hash        = d7cee96abd82c09afab50873bb07271d112684ccad3be4127a995ff8501cd2fe
P4.7 interest_hash    = 62d28c383697a01c5b96ec6e9c72b3e71a8fbf5e51a76ddeccacae3885decd2e
```

Accepted P4.7 bounded composition contract:

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

P4.7 uses a temporary minimal Godot project so unrelated gameplay/Breakpoint MCP autoloads do not contaminate the ecology gate. `project.godot` and production runtime were not changed; unexpected Godot `ERROR:` remains fail-closed.

P4.7 is an accelerated deterministic bounded integration soak, **not** a wall-clock production-duration soak.

## Final P4.8 evidence

Final control-only gate ran on:

```text
HEAD = 186c6d164b0bf17fc17e91a23136663edbe1c06d
runner blob = fa91e68f877551d0d08cea38382543ab23b9c4ac
```

Observed final marker:

```text
ECO.P4.8 FINAL GATES: PASS
```

Accepted P4.8 validation:

```text
validation/ecology/eco-p4-8-acceptance-preparation.json
blob = af886544d92970a061d47c29b76888fefbb66da6
```

## Next control boundary

P4 implementation/lifecycle work on this branch is complete. Do not extend P4 merely to keep the branch active.

Next step:

```text
branch-local P4 evidence complete
        ↓
independent review / evidence freshness check
        ↓
main-owned promotion / convergence decision
        ↓
human runtime merge gate where applicable
```

Per project control, this branch reports execution facts. It does **not** make `main` globally declare P4 accepted by itself.

## Repository-local workflow

Canonical entrypoint remains:

```text
RUN_ECO_TEST_WORKFLOW.ps1
```

The accepted P4.7/P4.8 evidence is durable and should not be regenerated merely to continue documentation or promotion work unless a reviewed/runtime surface changes and invalidates freshness.
