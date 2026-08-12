# GLOBAL-P0 R3 Refresh R1 — pre-promotion package

**Checkpoint:** `R3_PREPROMOTION_PACKAGE_READY`  
**Candidate:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**PR:** `#85`  
**Candidate construction base:** `1112d1f7cfad1df18fb3621a537e191e674848c6` / registry `75`  
**Preparation observation main:** `4a42c2fb6befb386f5c3eb48d9ba070745e25bbb` / registry `77`  
**Pre-package candidate head:** `fbc563c80eb55e960356f23e91bfb8f436bbff9a`  
**Observed runtime frontier:** `H0.1 R7 / PR #88 @ 107603a29c3776cc3fe7e94693e90aaaf15fa603 / VERIFYING_C22_COMPLETION`  
**Risk:** `CRITICAL`  
**Promotion:** `NOT AUTHORIZED`  
**Merge:** `NOT AUTHORIZED`

This checkpoint is preparation-only. Historical SHA/generation values identify provenance; they are never authorization for promotion or new runtime work.

## Result

```text
R3_PREPROMOTION_PACKAGE_READY
```

### READY_NOW

- R3 ownership/intersection review is prepared.
- R2 → R3 transition policy is refreshed for H0.1 R7 / C22.
- Evidence Map structure and exact completion criteria are prepared.
- Reviewer checklist is prepared.
- Verifier checklist is prepared.
- standard PC0 execution plan is prepared.
- directional-PC0 execution plan is prepared.
- current-main freshness/repin procedure is prepared.
- promotion checklist is prepared.
- post-promotion PC0 checklist is prepared.
- no runtime/domain code is part of this preparation package.

### REQUIRES_POST_C22_REPIN

All of the following must become true from fresh canonical state:

1. `C22 MAIN_INTEGRATED` is visible on `origin/main`.
2. H0.1 no longer owns the runtime worker slot.
3. fresh `origin/main` SHA is captured.
4. fresh registry generation is captured from canonical main.
5. PR #85 is rebased/repinned onto that exact main.
6. every ephemeral R3 source pin/frontier guard is refreshed; construction-base values `1112d1f7.../75` remain provenance only.
7. `CONTROL_PROJECT` passes on the repinned exact head.
8. standard PC0 is `NON_RED`.
9. directional-PC0 is `NON_RED`.
10. ownership/intersection review is repeated against fresh main.
11. R2 → R3 transition audit is repeated against fresh main.
12. Evidence Map is finalized for the tested exact head.
13. independent Reviewer = PASS.
14. independent Verifier = PASS.

### REQUIRES_HUMAN_GATE

Even after all automated/static gates above pass:

```text
GLOBAL_ARCHITECTURE_PROMOTION
```

must be explicitly approved by a human. This branch must not promote or merge itself.

## Ownership/intersection review

The candidate is acceptable only if these invariants stay true after repin:

- `ITEM` remains the stable canonical item truth foundation. H may consume/orchestrate item runtime behavior but cannot own item semantics, identity or canonical graph truth.
- `MATTER`, `Construction`, `G`, `NX`, `DATA` keep their domain ownership. R3 may define intersections/adapters but cannot silently transfer truth to H.
- `V0` remains a composition/presentation/visibility/readback consumer. It cannot create an independent terrain, inventory, character, construction, persistence or network truth.
- `H0.3` remains launch/restart/dev-session scaffold. It must not become the game-runtime scheduler or game-time authority.
- `ECO` remains Evolutionary Ecology advisory/research. It is not economy, not a mandatory foundation gate and not a runtime scheduler.
- future economy stays `ECON`, avoiding the ECO program-ID collision.
- `H0.1` is the sole runtime owner only while its current runtime frontier is active. Once C22 is `MAIN_INTEGRATED`, that slot must be released before R3 finalization.
- `NX.C1` cannot start merely because C22 is integrated. It starts only from fresh canonical **post-R3** main.
- no stale SHA, registry generation, branch-local state, chat history or historical evidence can authorize a new work order or promotion.

## R2 → R3 transition audit

Pre-promotion audit result: `PASS_PREPARATION_ONLY`.

Preserved:

- frozen/accepted R2 evidence remains valid historical evidence;
- canonical R2 foundations are not rewritten merely to relabel architecture revision;
- stable ITEM/MATTER/Construction/G/NX foundations are not replaced;
- active R2 runtime work must reach a safe boundary before promotion;
- research/advisory ECO remains advisory;
- V0 remains consumer-only;
- no runtime ownership expands in the R3 candidate.

Changed only at control/architecture-candidate level:

- explicit R2 → R3 transition rules;
- explicit stale-authorization fail-closed rule;
- explicit C22 → R3 repin boundary;
- explicit post-R3-only NX.C1 authorization;
- ECO/ECON naming separation.

## Current-main freshness procedure

After `C22 MAIN_INTEGRATED`:

```powershell
git fetch --prune
git switch control/global-p0-r3-refresh-r1
git status --short
git rev-parse origin/main
git rev-parse HEAD
git merge-base origin/main HEAD
```

Before any rebase, record the returned SHA values in the R3 evidence package.

Then:

```powershell
git rebase origin/main
git rev-parse origin/main
git rev-parse HEAD
```

Re-read from the rebased checkout:

```text
PROJECT_CONTROL.md
docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
docs/plans/H_PRIMARY_EXECUTION_ROADMAP_RU.md
config/control/project-program-registry.v1.json
config/architecture/global-p0-r3-architecture-candidate.v1.json
config/control/architecture-ownership-r3-candidate.v1.json
config/control/global-p0-r2-to-r3-transition-policy.v1.json
```

Fail closed if any of these disagree about current primary lane, runtime slot owner, C22 state, R3 gate, architecture revision or registry generation.

## Standard PC0 execution plan

On the rebased exact head:

```powershell
powershell -ExecutionPolicy Bypass -File .\CONTROL_PROJECT.ps1
```

For final Evidence Map binding, run again with the exact map path once it is finalized:

```powershell
powershell -ExecutionPolicy Bypass -File .\CONTROL_PROJECT.ps1 -EvidenceMap .\artifacts\control-global-p0-r3-refresh-r1\evidence-map.json
```

Acceptance:

- exit code `0`;
- project-control overall health is not RED;
- repository validation passes;
- registry validation passes;
- no stale-main/stale-registry authorization;
- no second runtime writer;
- current dashboard is derived from current machine registry.

Any RED or freshness mismatch blocks promotion.

## directional-PC0 plan

Run after the fresh rebase and registry refresh:

```powershell
python .\scripts\control\project_control_directional_watch.py
```

Review producer changes against every active consumer `watched_paths` and `critical_watched_paths`.

Expected R3 mutation window remains architecture/control/docs only. Any runtime/domain file in the R3 diff is an immediate scope failure.

Critical intersections to inspect manually even if automated output is NON_RED:

```text
R3 -> H0.1/H-primary
R3 -> ITEM
R3 -> NX
R3 -> G
R3 -> MATTER
R3 -> Construction
R3 -> V0
R3 -> ECO
R3 -> DATA-S1
```

## Reviewer checklist

Reviewer must independently answer PASS to all items:

- [ ] Candidate diff contains no runtime/domain implementation.
- [ ] C22 is `MAIN_INTEGRATED` on fresh main.
- [ ] H0.1 runtime slot is released.
- [ ] R3 candidate base/head pins correspond to the fresh post-C22 epoch.
- [ ] ownership manifest preserves ITEM/MATTER/Construction/G/NX truth.
- [ ] V0 is consumer-only.
- [ ] H0.3 is not a game-runtime scheduler.
- [ ] ECO is advisory/research and ECON is the future economy name.
- [ ] NX.C1 remains blocked until post-R3 canonical main.
- [ ] R2 frozen evidence is evidence, not runtime authorization.
- [ ] stale SHA/registry state fails closed.
- [ ] standard PC0 = NON_RED.
- [ ] directional-PC0 = NON_RED.
- [ ] Evidence Map names the exact tested head.
- [ ] no architecture promotion has already occurred.

## Verifier checklist

Verifier must reproduce facts independently rather than trusting the candidate text:

- [ ] `git fetch --prune`.
- [ ] independently capture `origin/main`, candidate head and merge-base.
- [ ] inspect canonical registry generation directly from `origin/main`.
- [ ] run `CONTROL_PROJECT.ps1`.
- [ ] run directional watch.
- [ ] compare `origin/main...HEAD` changed files.
- [ ] confirm only allowed control/architecture/docs/evidence surfaces changed.
- [ ] confirm C22 boundary and runtime-slot release from canonical control state.
- [ ] confirm ITEM/V0/H0.3/ECO/NX.C1 invariants.
- [ ] confirm Evidence Map exact-head binding.
- [ ] return PASS only if no stale authorization is used.

## Promotion checklist

Only after post-C22 repin/review/verifier success:

- [ ] fresh main SHA/generation recorded;
- [ ] C22 MAIN_INTEGRATED;
- [ ] H0.1 runtime slot free;
- [ ] exact R3 candidate tested;
- [ ] PC0 NON_RED;
- [ ] directional-PC0 NON_RED;
- [ ] Evidence Map complete;
- [ ] Reviewer PASS;
- [ ] Verifier PASS;
- [ ] R2→R3 audit PASS;
- [ ] ownership/intersection audit PASS;
- [ ] human `GLOBAL_ARCHITECTURE_PROMOTION` explicitly granted.

STOP before the final item is explicitly granted.

## Post-promotion PC0 checklist

After human-authorized promotion/merge, refresh main again and verify:

```powershell
git fetch --prune
git switch main
git pull --ff-only
git rev-parse HEAD
git rev-parse origin/main
powershell -ExecutionPolicy Bypass -File .\CONTROL_PROJECT.ps1
python .\scripts\control\project_control_directional_watch.py
```

Required state:

- canonical main declares R3 consistently;
- project registry/dashboard/ownership references agree;
- no H0.1 runtime slot survives as an active writer from the closed C22 frontier;
- ITEM remains stable foundation;
- V0 remains consumer-only;
- H0.3 remains non-scheduler scaffold;
- ECO remains advisory/research;
- only now may NX.C1 preparation create a fresh branch/work order, and it must use this post-R3 current main or a later explicitly audited descendant.

## Exact next step after `C22 MAIN_INTEGRATED`

```text
FETCH fresh main
→ confirm H0.1 runtime slot released
→ repin/rebase R3 PR #85 to exact fresh main
→ refresh ephemeral source SHA + registry-generation guards
→ run CONTROL_PROJECT
→ run standard PC0 + directional-PC0
→ finalize exact-head Evidence Map
→ independent Reviewer + Verifier
→ present human GLOBAL_ARCHITECTURE_PROMOTION gate
→ STOP
```

No promotion/merge is performed by this preparation checkpoint.
