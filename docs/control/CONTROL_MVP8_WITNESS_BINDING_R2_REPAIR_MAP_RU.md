# CONTROL MVP8 reviewer witness persistence R2 — fail-closed repair

Base exact PR #839 HEAD `a2a8e93f065f9cee8fc8a39eb03df29be322c786`
TREE `e4622f57ec1b86d9193f0675c96f8e67cd9c1d97`.
Source case: [original independent reviewer RED #40063151255](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40063151255);
[review PR #839 finding](https://github.com/rootfabric/distributed-world-simulator/pull/839#issuecomment-6379959426).
**Scope:** five-file repair in separate Draft branch `repair/control-mvp8-pr839-committed-witness-binding-r2`. This is NOT a merge or an independent Reviewer approval. Parent PR #834 and #839 stay frozen.

## Confirmed RED — witness from uncommitted local input

```text
REVIEW_WITNESS_IN_HEAD=false
REVIEW_WORKTREE_WITNESS_IGNORED=true
REVIEW_STATUS_EXIT=0
REVIEW_STATUS_OK=True
```

A disposable local Git branch was created **above the original exact frozen subject**, removed the authorizing `external-role-event-witness.v1.json` from HEAD, then restored only its working-tree bytes under a Git ignore rule. `git status --porcelain -- witness` was empty but the Harness trusted `read_json(witness)`, allowing a non-ancestor Reviewer event. This violates "Git is durable memory" even though the real original PR839's **committed** witness is legitimate.

## Root cause / fix location

In `scripts/harness/state_builder.py::_external_reviewer_witnesses`, the original guard only checked `git status --porcelain -- witness`, which does not list ignored untracked or `assume-unchanged` tracked-file modifications.

Narrow repair **before parsing the witness**:

1. Require `git --no-replace-objects rev-parse HEAD:<exact path>` to find a valid committed Git blob; otherwise `EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_COMMITTED`.
2. Compare `git --no-replace-objects hash-object --no-filters -- <path>` with that blob; mismatch or dirty status → `EXTERNAL_REVIEW_WITNESS_MANIFEST_DIRTY`.
3. Require exact single original path-history addition and no later edits; rewritten committed witness → `EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_IMMUTABLE`. Full git-origin ancestry unchanged.

Original exact Reviewer witness/commit, event and receipt blobs remain untouched; no new owner or second authority.

## Novel falsifiers and acceptance gates

- Original independent source RED in [review-only branch](https://github.com/rootfabric/distributed-world-simulator/tree/review/control-mvp8-pr839-untracked-witness-falsifier-r1) is retained as evidence. Normative R2 test repeats same scenario on its exact new HEAD and MUST turn GREEN via rejection.
- Additional adversarial cases: tracked file marked `assume-unchanged` with modified on-disk bytes is refused; explicitly committed rewrite of manifest is refused by one-add history guard.
- Six existing witness tests, five immutable-map tests, and full Harness regression suite must still PASS on Linux; all new falsifiers and `CONTROL_DEVELOPMENT.ps1 -Status` on Windows.
- Separate `-CheckConsistency` and PC0/directional diagnostics must be reported with their actual exit and health values, **not** mistaken for this fix's local regression PASS.
- Require exact `git diff` parent → new subject contain ONLY: state builder, new regression script, scoped workflow, report. No historic event/review/manifest rewrites.

## Review disposition

Original PR #839 exact HEAD = `REVIEW_FAIL` for uncommitted ignored witness.
This candidate is `IMPLEMENTER_REPAIR_PENDING_EXACT`, requires new full tests
and a **fresh independent Reviewer and Verifier** on its published new HEAD.
No self-issued role signoff, no PC0 implication, no merge or direct main push.
