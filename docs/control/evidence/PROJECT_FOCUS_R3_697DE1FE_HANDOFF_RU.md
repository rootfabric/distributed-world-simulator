# PROJECT-FOCUS AUTONOMY REPAIR R3 — durable handoff

## Exact source

- Subject HEAD: `697de1fe6bb6bf934575f4280975d190b9fa948a`.
- Subject TREE: `5ffbf66eb5a42a8731f13880adc93fff3bf7be02`.
- Canonical main observed: `c9e3b9d311818c5c55f16861d6c298aba5458990`.
- Source branch: `control/project-focus-harness-reconciliation-r1`; draft PR #547.
- Work Order: `PROJECT-FOCUS-AUTONOMY-REVIEW-REPAIR-R3`.

This is Implementer mechanical evidence and a resumable handoff, NOT an independent Reviewer/Verifier verdict, checkpoint acceptance, merge approval or runtime authorization.

## Published changes

`0f2e01731003609a5d8a647bf58a987d4009341e`: committed typed hard-block proof, real build_state -> CLI -> continuation path, shared review/manifest/artifact SHA256 validation in loader and event guards, historical compatibility, production-route tests and bounded-execution documentation.

`db5dab089f36796a28b639d3b24e05486983b0ad`: incorporates already accepted main scale-campaign guard and tests; refreshes both observed-main pins. No change to the original production-provenance repair.

`697de1fe6bb6bf934575f4280975d190b9fa948a`: fixes the fresh review finding on legacy-generation selection. Reads the committed registry/epoch and rejects dirty registry, epoch and authority-policy inputs; adds real Drive/CloseMission, forged guard-context and policy-downgrade regressions. Historical replay remains distinct from active authorization.

No runtime/scenes, existing execution ledger, reviews, evidence or acceptance records were modified. No P7 implementation restarted; no P7 acceptance/MVP activation/runtime lease was issued.

## Exact mechanical validation

Executed on clean tracked checkout of the subject:

```text
python -m unittest discover -s tests/harness -p test_*.py -q
----------------------------------------------------------------------
Ran 238 tests in 27.070s

OK (skipped=2)
exit_code = 0
```

Two skips are existing offline proposed-R3 live-GitHub guards. They are not silently counted as executed tests. Full quiet-log SHA256: `b2b8e44bd3170b5be3ce31acc7c297023a6bc10a5d95adf73b86e627fef3748a`.

Strict candidate JSON/duplicate-key/schema/registry/lease validation: exit 0; comparison base `c9e3b9d311818c5c55f16861d6c298aba5458990`, candidate generation 81. Candidate Overview and CheckConsistency: exit 0, `CANDIDATE_NON_AUTHORIZING`, runtime_authorized=false.

Canonical commands used the Python backend, not a claimed Windows wrapper run:

```text
python -m harness.cli overview          -> exit 0
python -m harness.cli check-consistency -> exit 3, PROJECT_CONSISTENCY_ERRORS
python -m harness.cli drive             -> exit 3, EPOCH_REGISTRY_GENERATION_MISMATCH
python -m harness.cli close-mission     -> exit 3, EPOCH_REGISTRY_GENERATION_MISMATCH
```

The canonical P7 execution is still generation 80; the control candidate is not merged. These fail-closed outputs do not authorize mission closure or old P7 runtime dispatch.

Environment: Linux, Python 3.13.5, pinned jsonschema 4.22.0, PYTHONUTF8=1. Tracked checkout clean before and after. Normal git fetch failed DNS; live refs were read through the connected GitHub API, and local commit/tree identities were checked against Git objects. This is not reported as a successful normal git fetch.

One aggregate local command exceeded the tool execution window before the test summary; it was NOT counted. Subsequent separate complete test execution returned exit 0. Interrupted and completed logs remain distinguished in the complete local evidence package.

## Exact CI and Project Control

- Run: `34011494430`, source HEAD `697de1fe6bb6bf934575f4280975d190b9fa948a`, conclusion `success`.
- Artifact: `9982599288`, name `project-control-report`, 28239 bytes.
- Downloaded archive SHA256 checked: `9fe1ab0ad8986cbaebb818f1409ee064c3e586e27659e2d8198a21a210ae1927`.
- Standard PC0: YELLOW; JSON SHA256 `22f97143d070bc14ea49aae64da6ded4d1ca18fc4f2fa7f2bae4815e5f9ec2f3`.
- Directional PC0: YELLOW; JSON SHA256 `4c61495140cc711314c48348b8e1243ae06bced6c7fba90f30557484aea73637`.
- Research-local G/ECO RED and pre-existing directional watch findings are not hidden; no project-wide GREEN is claimed.
- Artifact retention expires 2026-12-05T04:26:11Z. Full reports/logs are available in the downloaded archive; this handoff does not claim those complete raw files are embedded in Git.

Historical CI `34010284231` on `0f2e0173` failed candidate consistency after main moved; it is not relabeled success. Historical db5 CI `34010699637` does not replace current-head CI.

## Independent roles and next action

Fresh exact Reviewer requested in #547 comment `5556882608`. Do not infer its final verdict from this Implementer record or from an earlier subject's review.

An independent executable Verifier request on the predecessor was rejected by the external Codex service because the repository environment was missing: request `5556754609`, response `5556755342`. This is distinct from available local mechanical execution. A fresh eligible independent role must verify this subject; old Windows R1/R2 PASS cannot be transferred to it.

Next action: collect fresh exact Reviewer result and independent Verifier evidence for `697de1fe`; resolve any mandatory finding with a bounded repair, or, after sufficient independent evidence and a fresh main check, request the separate human MERGE/HOLD decision for #547. Keep source frozen while roles evaluate it. Evidence-only publication must not change the source subject.

## Why the earlier session failed to converge

Synthetic tests concealed missing production provenance and a missing state-loader path; policy declarations did not enforce evidence at their consumers. Later source/control changes invalidated earlier exact review. Concurrent main updates invalidated observed-main pins. The separate Verifier task had an external environment blocker. Repeating status reads or promising background progress did not resolve any of these causes.

The bounded repair now has committed code, exact test results and a next action. Mission completion is still not declared. No unsupported HARD_BLOCKED/ACCEPTED record was manufactured to force CloseMission to succeed.

## Not checked here

Fresh Windows PowerShell wrapper on this subject; Godot archive/binary identity; P7 full runtime gate; canonical P7 acceptance; MVP activation; multi-client graphical MVP; current freshness of every remote research branch in the DNS-restricted local checkout.
