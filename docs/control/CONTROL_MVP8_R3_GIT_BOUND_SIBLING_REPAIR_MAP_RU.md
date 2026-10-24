# CONTROL MVP8 R3 — Git-bound Reviewer event and receipt repair

**Issue:** [#848](https://github.com/rootfabric/distributed-world-simulator/issues/848).
**Exact parent:** PR #845 @ `3a8f858f85c5ff018676557650f34179d6d5f86b` (TREE `f03f89297f1cb97ed4df9b4b8ecedfc1fef2aec3`).
**Branch:** `repair/control-mvp8-pr845-git-bound-siblings-r3`. **Draft, no merge, no main changes.** Parent PR #845 has genuine `REVIEW_FAIL` and remains frozen.

## RED — source of the defect

Fresh adversarial Reviewer ran two new falsifiers against the unchanged exact PR #845 source in independent named Git worktrees. [CI #40065997560](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40065997560), [blocking review](https://github.com/rootfabric/distributed-world-simulator/pull/845#issuecomment-6380356062). `git update-index --assume-unchanged` suppressed `git status` while altering the raw event #0050 or Reviewer receipt bytes:

- event original blob `b27cc80072fcb66cb217004ddad35aeb381d37a0` vs uncommitted `240aa6e8221aece9f8803116423f10727cff51ab`;
- Reviewer receipt original blob `3759b7caf84ef1e49a894ae2d6b5934e676c15b5` vs uncommitted `da6f021d95347460258c6f218d1fbb5aa1b81a56`.

Both changes were incorrectly accepted by the one-event witness as `exit0`. R2 checked the *manifest* Git blob, but the privileged evaluator consumed event and receipt JSON from the live worktree without verifying their exact original bytes.

## R3 — minimal canonical fix

Extend `scripts/harness/state_builder.py::_external_reviewer_witnesses`. Once the existing `HEAD:event`, `HEAD:receipt`, external reviewer commit, parent and TREE Git objects are independently verified, the evaluator **reads raw live event and receipt bytes once per file**, computes Git's raw `hash-object --stdin` over **the very same byte buffer**, and parses only that verified byte buffer with duplicate-key detection. The raw blob hash must match the already witnessed `HEAD:path` blob SHA. This is **not** `git status`-only or a hash-then-reread pattern.

- Altered local event fails closed `EXTERNAL_REVIEW_WITNESS_EVENT_LOCAL_BLOB_MISMATCH`.
- Altered local Reviewer receipt fails closed `EXTERNAL_REVIEW_WITNESS_RECEIPT_LOCAL_BLOB_MISMATCH`.
- A caller-supplied Python event dict that differs from the independently Git-bound event content fails `EXTERNAL_REVIEW_WITNESS_EVENT_DTO_MISMATCH`. Equality is compared with deterministic, type-strict JSON encoding (not Python dict `==`, which treats `False == 0` and `50.0 == 50`); unencodable/NaN objects also fail closed.
- A genuinely authentic event, receipt and original single-event witness continue to be accepted.

**No changes** to original witness manifest, event ledger, independent Reviewer receipt, transition table, event schema, canonical ownership, Godot or FABRIC runtime. The original Git ancestry guard remains required for all other events. This does **not** convert a Reviewer PASS into a merge or human acceptance.

## Normative tests and possible blockers

New `tests/harness/test_mvp8_git_bound_sibling_inputs_r3.py` tests authentic input, hidden uncommitted event #0050, hidden uncommitted review receipt, forged in-memory DTO, and numeric/boolean type-confusion DTO aliases. Tests use clean named worktrees with unique names and remove their worktrees/branches on exit. RED original source, GREEN R3 candidate must be demonstrated.

Preserve previous R2 **4-case**, R1 **6-case**, and MVP8 evidence-map **5-case** tests; run full Harness suite, native Windows `CONTROL_DEVELOPMENT.ps1 -Status` / `-CheckConsistency -Candidate`, Linux exact `status` / `check-consistency --candidate`, standard and directional PC0, inspect raw logs and SHA256SUMS. Report actual non-RED/RED findings without treating `--no-fail-on-red` exit0 as architectural approval.

**Risk:** HIGH — authorization of a non-ancestor Git Reviewer event. **Scope:** one harness implementation source, one new test file, one scoped CI, this Repair Map. **Human gates:** independent fresh Reviewer and separate Verifier on new frozen R3 exact-head plus required PC0/directional audit and explicit main merge approval. **MERGE_READY=false** until then.
