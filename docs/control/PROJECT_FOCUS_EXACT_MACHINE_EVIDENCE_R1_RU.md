# PROJECT-FOCUS — exact machine evidence R1

Дата: 2026-09-05. Parent mission: PROJECT-FOCUS-CONTROL-VALIDATION-R1.
PR: #547. Evidence carrier only: `control/project-focus-exact-evidence-r1`.
Не вливать carrier в frozen candidate во время независимой проверки.

Статус: EXECUTABLE_CONTROL_CHECKS_RECORDED / INDEPENDENT_ROLES_PENDING.
Этот документ записан Implementer-ом. Он не является независимым Review,
Verification, checkpoint acceptance, human merge approval или runtime authority.

## Единственный проверяемый subject

- HEAD: `1b87bb0908429f5bbae2eb5929a07649ed5507d4`.
- TREE: `31fe1abd8fea945645877e5fb8bc6bf40469efcb`.
- Candidate branch: `control/project-focus-harness-reconciliation-r1`.
- Canonical main: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.
- Canonical main TREE: `af9abf6def54d231d055cfc1f6af14cbf10d787f`.
- Candidate registry generation: 81; canonical main generation: 80.
- Full main-to-subject diff: 34 files, no runtime or scenes changes and no
  `config/control/harness/executions/` or `config/control/harness/acceptance/` changes.

Initial main-to-6b80271d comparison was ahead 2 / behind 0; main did not advance
in the observed control CI/export runs. All candidate repairs were fast-forward
commits; no force-push, rebase, historical rewrite or merge was executed.

## Штатный exact-head CI

Workflow: `.github/workflows/project-control.yml`.
Run: `33957574205`. Job: `101283573478`.
https://github.com/rootfabric/distributed-world-simulator/actions/runs/33957574205

GitHub conclusion: SUCCESS. EXPECTED_HEAD and ACTUAL_HEAD both equal the subject.
Environment: GitHub-hosted Ubuntu 24.04.4, Python 3.12, pinned jsonschema 4.22.0.

Recorded suite results, failures/errors zero:

| Suite | Tests |
|---|---:|
| Project overview | 7 |
| Harness checkpoint session | 22 |
| Architecture / ownership compatibility | 65 |
| H0.2 machine checkpoint | 8 |
| V0 product checkpoint / product policy | 24 |
| Generation-80 guards / directional clearance | 19 |
| Complete Harness discovery | 167 |

The full discovery is a union, not an additional unique-test count.
Full CI discovery: 167 tests, 0 failures, 0 errors, 0 skips. Both live-GitHub
historical-ref tests executed. The candidate consistency command returned exit 0,
no findings, and CANDIDATE_NON_AUTHORIZING provenance.

Schema step uses repository-owned duplicate-key rejecting `read_json`, validates
24 required/changed JSON documents, checks all five registered Draft 2020-12
schemas and the additional output schema, and checks generation/lease agreement.
This does not invent a JSON Schema for policy documents that have none.

## Project Control: не подменять отчёт зелёным job

Both standard and directional reports declare overall YELLOW and read canonical
main generation 80, not candidate generation 81. Standard V0 findings are empty.
Directional CH→NX and NX→T are YELLOW watch hits. V0→G and V0→ECO are unresolved
RED advisory findings with `global_blocking=false`; they were not erased or
reclassified. No global-blocking RED is present in these reports.

Existing policy gates for P7 acceptance, unrelated foundation stages and runtime
mutation remain in the report. SUCCESS of a workflow using `--no-fail-on-red`
does not prove project acceptance or discharge independent review.

Artifact ID: `9966861374`, name `project-control-report`.
ZIP SHA256: `d1ade58dcd25d4714543c4e6bb551e1c20c9588c6db23aef16744ff2637367a4`.
Downloaded report SHA256:

- project-control-report.json: `3f7cc75bda891d99f1b26e6b86cb6bf2cbf27f4f09de7ab57a4f753f426d9f52`.
- directional-watch-report.json: `fb9a7e5e7a23e3075ac9c9fb458cadef2b4db03736113496b3bb4b069908d2ca`.

## Local exact execution and environment provenance

Initial local fetch failed: DNS could not resolve github.com. No local ref was
invented as a substitute. Repository-owned export pattern was used through
validation-only draft PR #548 / run `33957130311`: live `git fetch --all --prune`
and both required rev-parse commands ran on GitHub Actions, followed by exact
HEAD/TREE and clean-tracked checks. The exported subject was 44eacbc8 with full
Git metadata and no persisted credentials. Source archive and wheel digests
were checked; pinned jsonschema 4.22.0 was installed locally offline.

Source tar SHA256:
`9453eb77dc1d0eaeda80314e320170c622ba64e0e9cecffbab2e95c97013e768`.
The later remote commit 1b87bb09 was reconstructed from its actual Git API
metadata/content and accepted locally only after its Git object hash exactly
matched the published SHA. Its complete tree hash also matches GitHub. This is
not a claim that a later local network fetch succeeded.

Local exact detached checkout before and after all commands: subject HEAD/TREE,
clean tracked status. Local Python 3.11.8. Complete discovery: 167 tests, exit 0,
0 failures/errors and 2 existing live-GitHub-only skips; CI covered both skips.
The exact workflow schema/duplicate validation step also returned exit 0.

PowerShell is unavailable locally. The commands below executed the same
repository Python backend used by CONTROL_DEVELOPMENT.ps1, not the PowerShell
wrapper itself. No candidate option was supplied to Drive or CloseMission.

| Command | Exit | Actual result |
|---|---:|---|
| python3 -m harness.cli overview | 0 | canonical main snapshot; COORDINATION_NOT_DECLARED finding |
| python3 -m harness.cli check-consistency | 3 | PROJECT_CONSISTENCY_ERRORS; focus absent in canonical main |
| python3 -m harness.cli overview --candidate | 0 | MVP / closure hold; CANDIDATE_NON_AUTHORIZING |
| python3 -m harness.cli check-consistency --candidate | 0 | no consistency findings; still non-authorizing |
| python3 -m harness.cli drive | 3 | EPOCH_REGISTRY_GENERATION_MISMATCH |
| python3 -m harness.cli close-mission | 3 | EPOCH_REGISTRY_GENERATION_MISMATCH |

All six JSON envelopes satisfy the output schema. Drive/CloseMission did not
reach an authorized mission exit. Their result is not exit 8, not acceptance,
not a reason to edit the historical generation-80 epoch, and not permission to
run P7 or MVP. Post-control-merge canonical commands still need execution.

Local durable-log digest index:

- local-validation-envelope.json: `f9b4cfa90dfb491d8f70121e839fa326b513910e097ef2c67602deb8dd1459fc`.
- scope-diff.json: `2005e3deb7e450711486f9f32340becb02dcc9575b4a697a5ff3939ce622bb1e`.
- full-harness.stderr: `c0ff9b3dcdf87ac685fee62278f5a11eb20b746b0b47e36d78939fc5846ca7a4`.
- schema-duplicate-validation.stdout: `90564e43aa912fa63179fdae7e84f43090dd7ff5720ded8e1a24a04f425a33f5`.
- drive-main.stdout: `0498342eb13f1ccb039b8e45ef3f1076020afa874330a6c1b9d6415c6d32983b`.
- close-mission-main.stdout: `9f902d05ac28041169b1016ec70d517955a2df2a5e8d3c1bf6c8169f01071839`.

## Fresh independent role requests

Separate bounded requests were actually posted in PR #547:

- Reviewer: PROJECT-FOCUS-CONTROL-REVIEW-R1, comment `5550860808`.
- Verifier: PROJECT-FOCUS-CONTROL-VERIFY-R1, comment `5550862231`.

Both pin the same subject HEAD/TREE and forbid candidate mutation, self-acceptance,
runtime execution and merge. Verifier may add only new evidence on a separate
branch. Codex bot comment `5550862333` confirms Code Review running at 1b87bb0;
it is not a result. No completed fresh Reviewer or Verifier decision is recorded
in this document. Old static records for 2a502c28 do not cover this subject.

## Непреодолённые gates и следующая последовательность

First obtain exact independent Reviewer and Verifier results, resolve findings
without weakening tests, and only then request human merge approval for #547.
A subject-changing repair requires a fresh exact-head review cycle.

The canonical acceptance directory at observed main contains EG/P4/P5/P6/SM1
records, not a P7 checkpoint acceptance. P7 runtime #487 remains merged but not
formally accepted by this work. Phase 2 closure runtime/acceptance and phase 3
MVP activation/epoch/WO/lease have not started. Godot and the P7.7 2032-assertion
post-merge gate were not run in this control phase.

No new canonical checkpoint acceptance, MVP activation commit, Project Epoch,
runtime Work Order or runtime lease has been created. Historical evidence is
unchanged. Parent mission remains open.
