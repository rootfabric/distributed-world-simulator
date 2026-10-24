# CONTROL MVP8 PR845 — fresh adversarial review R1

**Verdict: REVIEW_FAIL / 2 blocking findings. Merge-ready: false.**

Reviewed exact source: `3a8f858f85c5ff018676557650f34179d6d5f86b` / TREE `f03f89297f1cb97ed4df9b4b8ecedfc1fef2aec3` (Draft PR #845). This is a fresh review in the assistant session, separate from prior-turn implementation, but not a second separately authenticated human/agent signature. No reviewed product files or main changed.

## Independent reproduction

[Review-only run 40065997560](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40065997560) ran two novel RED falsifiers in clean disposable named Git worktrees anchored on the exact reviewed subject. Artifact 12549690454, archive SHA256 `49078a9329b843ba2f5d710f2c5e0ccce02430b01913cb4efc964b6a092e2e4a`; two inner SHA256SUMS MATCH.

Both tests first prove that `git status --porcelain` is EMPTY because of `git update-index --assume-unchanged`, even though `git hash-object --no-filters` on the live file is different from `HEAD:<file>`. The unchanged proof functions return authorization success (exit 0), which is the unexpected/red result.

### Finding A — event #0050 local JSON not Git-bound

Original event blob: `b27cc80072fcb66cb217004ddad35aeb381d37a0`. Modified local event summary blob: `240aa6e8221aece9f8803116423f10727cff51ab`. `REVIEW_SIBLING_UNCOMMITTED_ACCEPTED=true`, exit 0. The function `_external_reviewer_witnesses` checks the Git HEAD blob but consumes caller-supplied event DTO without binding to that blob. The adjacent `_validate_event_git_provenance` checks only porcelain status, hidden by assume-unchanged.

### Finding B — review receipt live JSON not Git-bound

Original review receipt blob `3759b7caf84ef1e49a894ae2d6b5934e676c15b5`. Locally changed field `source_clean_after: false` yields blob `da6f021d95347460258c6f218d1fbb5aa1b81a56`; the unchanged reviewer-witness proof also returns exit 0. At `scripts/harness/state_builder.py` lines 251–257 the HEAD blob and external reviewer commit blob are verified, but at line 280 the local receipt JSON is read and only a subset of fields validated, not its raw bytes.

## Required repair R3

[Issue #848](https://github.com/rootfabric/distributed-world-simulator/issues/848) is the reproducible bug ticket. Narrowly bind both local file bytes and event DTO to the actual committed HEAD blob (or read trusted Git raw data directly); preserve the approved one-event exception and all original ancestry/immutability guards. Integrate both novel falsifiers into standard Windows+Linux acceptance alongside inherited R2 four cases, R1 six, schema five, whole Harness suite, fresh Status/CheckConsistency and PC0. Keep historic evidence and PR heads immutable.

Earlier CI #40063985232 3/3 PASS and 397/397 Harness PASS are valid for their stated coverage. They do not cover these new sibling mutations. The test-only Actions job succeeded **because it proved both RED failures**, not because PR845 passed.

**Final original subject code-review verdict: FAIL. Merge-ready=false.**
