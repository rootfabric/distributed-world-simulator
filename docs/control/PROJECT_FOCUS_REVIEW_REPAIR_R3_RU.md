# PROJECT-FOCUS — Fresh Reviewer Repair Map R3

Дата: 2026-09-05. Parent mission: PROJECT-FOCUS-CONTROL-VALIDATION-R1 / PR #547.
Risk: HIGH. Scope: existing control overview/CLI, tests, CI validation and this map.

## Exact reviewed input and reproduction

HEAD: `1b87bb0908429f5bbae2eb5929a07649ed5507d4`.
TREE: `31fe1abd8fea945645877e5fb8bc6bf40469efcb`.
Canonical main: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.
Independent Reviewer: chatgpt-codex-connector, review submitted 2026-09-05T09:32:44Z.
Review ID: PRR_kwDOTlKYmc8AAAABMTeNSQ; reviewed commit 1b87bb0908.

Two required P1 findings, not waived:

1. Review comment `3940152337`: candidate preview reports observed_main but does
   not reject a different current canonical main. Classification:
   CONTROL_CANDIDATE_BASE_DRIFT_NOT_BLOCKED. Owner: project_overview.py.
2. Review comment `3940152340`: CLOSE_ROLE uses mission_exit_allowed, preventing
   a completed independent role from handing off while P7 remains unaccepted.
   Classification: CONTROL_ROLE_AND_MISSION_GATE_CONFLATION. Owner: existing
   CLI adapter + execution state/continuation, not a new role authority.

New regression tests against unchanged input production code reproduced five
failing assertions/subtests (12 tests, exit 1). This is an actual reproduced
control defect set, not an inferred runtime failure or a test expectation waiver.

## Minimal correction

Candidate consistency emits product-blocking CANDIDATE_MAIN_DRIFT when its
observed_main is absent or differs from the pinned current canonical commit.
Canonical overview preserves observed_main as historical provenance; a merged
snapshot is not required to name its own future merge SHA. Existing CI therefore
uses canonical consistency when HEAD equals origin/main and non-authorizing
candidate consistency otherwise. No stale candidate gains a merge exception.

CLOSE_ROLE uses a separately derived role_exit_allowed. It resolves the selected
execution and reuses the existing build_state/continuation owner, including its
schema, generation, ledger and handoff checks. A stale generation is still
rejected. A completed role can hand off; an in-progress role cannot. The canonical
route retains exclusive mission closure and runtime hold authority. DRIVE, PLAN,
RESUME and CLOSE_MISSION still route before loading obsolete product epochs.

For an isolated closure role use CONTROL_DEVELOPMENT.ps1 -CloseRole -Execution
with its fresh declared execution path. No new epoch, execution, role result or
runtime lease is created by this repair. Default CloseRole uses the existing
execution selector; the old generation-80 P7 epoch is not silently authorized.

## Tests and next gates

Focused repaired working tree: 12 tests, exit 0. Full discovery: 172 tests,
0 failures/errors, 2 existing live-GitHub-only skips. These are pre-publication
diagnostics, not exact published-head acceptance. Required next: publish repaired
HEAD/TREE, repeat full exact CI including live tests, and obtain fresh independent
Reviewer and Verifier on that same new subject. Old 1b87 results remain attached
to their actual subject and cannot authorize the repair.

Tests include changed/missing main observation, canonical historical provenance,
independent role/mission flags in both directions, completed versus in-progress
REVIEW/VALIDATION roles and stale-epoch rejection. Existing runtime hold and
candidate-no-dispatch tests remain. No production guard is weakened.

## Bounded post-build critique

No second ledger, role owner, acceptance parser or scheduler was introduced.
The correction reuses current continuation machinery rather than accepting a
claimed handoff or granting unconditional role exit. The only CI routing change
selects the appropriate existing authority mode. No material refactor is required
beyond these reproduced defects. This is Implementer critique, not fresh review.

## Separate helper defect, not a production repair

Validation-only PR #549 / run `33958335130` / job `101285614538` checked exact
1b87 HEAD/TREE and then incorrectly passed unsupported -Json to the PowerShell
wrapper. The wrapper correctly rejected it with exit 2 / INVALID_INVOCATION.
PowerShell 7.6.5 was present; this is executor invocation error, not missing Godot
or a launcher product defect. Preserve the failed artifact `9967097294`:
ZIP SHA256 `8d70101d488f0c964755924c4a23ca6c8276fecc72b199b55e285d84be48809c`.
Fix the helper only: documented switches, retain full output and parse the JSON
line separately from Write-Host messages. Repeat it on the new frozen subject.

Runtime, scenes, historical events/reviews/evidence/acceptance and main unchanged.
P7 closure and MVP activation have not started; parent mission remains open.
