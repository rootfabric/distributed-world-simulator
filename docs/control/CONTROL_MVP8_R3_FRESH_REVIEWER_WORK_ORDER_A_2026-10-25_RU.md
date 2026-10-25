# CONTROL MVP8 R3 — Fresh Independent Reviewer Work Order A

**Dispatch status:** REVIEWER_PENDING; dispatch only (not a Reviewer signature).

**Subject:** [PR #855](https://github.com/rootfabric/distributed-world-simulator/pull/855) — `repair/control-mvp8-pr845-git-bound-siblings-r3`.
- PRODUCT_HEAD `7510aa4ff81e6d3a13bbfa0872b6f60bfb547621`
- PRODUCT_TREE `5003355e504c620c7f4bb0413bda6d4f36b9fd8d`
- EXACT_PARENT (PR #845) `3a8f858f85c5ff018676557650f34179d6d5f86b`
- Historical base lineage: #834 `a5ef36a1716f4d233351b38314fc70355447078c` → #839 `a2a8e93f065f9cee8fc8a39eb03df29be322c786` → #845 `3a8f858f85c5ff018676557650f34179d6d5f86b` → #855 frozen.
- Canonical main last observed: `aac301b9a9a89e027f6d99864437eb750a4202ca`; always re-fetch and report any drift.

## Independence and authority

Act as **fresh Reviewer**, distinct from the Windows Verifier who signed [VERIFIER_VERIFIED](https://github.com/rootfabric/distributed-world-simulator/pull/855#issuecomment-6396059268) and from the earlier Implementer who committed R3. If both roles would use the same actor, do not issue a formal independent signature; report `INSUFFICIENT_EVIDENCE` or request a distinct agent.

You may create fresh detached/named worktrees, test-only independent falsifier branches, GitHub CI and durable reviewer-only evidence. **Do not** change the frozen PRODUCT_HEAD, merge, force-push, direct-push to main, re-register or stop GitHub Actions runner, or reinterpret machine verifier PASS as code-review PASS.

## Work Order A: adversarial source review

1. Fetch exact R3 commit and parent. Check product HEAD/TREE, parents/merge-base, tracked clean, exact four changed paths (only `scripts/harness/state_builder.py`, `tests/harness/test_mvp8_git_bound_sibling_inputs_r3.py`, scoped workflow and Repair Map). Verify `git diff --check`, syntax and tests. No production Godot double or GPU required for this control-plane source review.
2. Independently review `_external_reviewer_witnesses`, `_read_exact_git_blob_json`, `_validate_event_git_provenance`, and callers in `build_state`. Trace *which bytes* are trusted through Git `HEAD:<path>` objects, `hash-object --stdin`, `json.loads`, event DTO and `reduce_events`. Explicitly check read-then-hash-then-parse is **same captured buffer**, no local object substituted after proof.
3. Check **historical exact pins**: witness blob `a2c07a8d7b24346abafa46513ed614b792126a97`; event #0050 blob `b27cc80072fcb66cb217004ddad35aeb381d37a0`; Reviewer receipt blob `3759b7caf84ef1e49a894ae2d6b5934e676c15b5`. Prove external Reviewer commit `6d1f3fbcbebee31d9be9745f82becc3439de57cc` direct child of reviewed product `dc6e7fffa27d764ea09ded949d50b99a32fa4d9b`; diff solely adds same exact Reviewer receipt. No second canonical authority.
4. Attempt to falsify with **new** independent negative probes beyond normative 5+4+6+5:
   - Git `assume-unchanged` and `skip-worktree` with mutated bytes;
   - receipt payload with unchanged parsed semantics but different raw bytes, duplicate JSON keys, Unicode/line-ending transformations;
   - in-memory event DTO `False` vs `0`, `50.0` vs `50`, nonfinite values, forged auxiliary fields;
   - manifest moved/removed/replaced or locally stale while `git status` appears clean;
   - non-ancestor or sibling unrelated events, wrong direct-parent reviewer, extra files in reviewer commit, changed reviewer receipt;
   - symlink/path traversal/parse errors and Git replace-ref behavior if applicable.
   Do not claim a potential defect until reproducible on frozen subject, with recorded paths/HEAD/blob and expected vs actual error.
5. Check neighboring consumers: the ordinary event ledger and existing reconciliation code must not silently allow **other** non-ancestor event subjects. Document any out-of-scope global ledger risks separately, never broaden R3 via an unreviewed fix.
6. Check `REQUIRED_FIXES` vs `RANK_UP_MOVES`, authority/ownership implications, review independence and compatibility across stack #834/#839/#845/#855. If a true high-risk bypass is found: `REVIEWER_FAIL`, freeze evidence and propose minimal R4, not source-mutating R3.

## Existing machine evidence (context, NOT review substitution)

- Fresh hosted Windows/Linux [run 40091993517](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40091993517): exact source 402/402 full Linux Harness; 20/20 focused Windows/Linux; Status/Consistency PASS.
- New source-only `skip-worktree` falsifiers [run 40175382790](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40175382790): 4/4 Windows and Linux PASS.
- Latest exact Windows/Linux/PC0 [run 40175732931](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40175732931): 20/20 each; Status and Consistency PASS; standard PC0 YELLOW, directional YELLOW (not GREEN), 3 existing snapshot warnings.
- Fresh independently acting Windows Verifier [comment 6396059268](https://github.com/rootfabric/distributed-world-simulator/pull/855#issuecomment-6396059268): exact HEAD/TREE/three Git blobs/20-of-20/native status and consistency, declared `WINDOWS_EXACT_PASS / VERIFIER_VERIFIED`.

These runs support machine reproducibility, **not** sufficiency of design/source review. Re-run additional probes where they materially change the verdict.

## Publication protocol

Publish a reviewer-only report as a comment directly in PR #855 with:
- `ROLE=FRESH_INDEPENDENT_REVIEWER` and reviewer identity/environment;
- exact PRODUCT_HEAD, TREE, BASE, current main ref and tracked-clean before/after;
- `REVIEWER_PASS | REVIEWER_FAIL | INSUFFICIENT_EVIDENCE`;
- source findings with file:line and concrete counterexamples, recorded raw evidence/CI run IDs and SHA256;
- distinct arrays `required_fixes`, `rank_up_moves`, `evidence_gaps`, `risk_assessment`, `scope_and_owner_assessment`;
- statement of no merge, no product change, no verifier-signature impersonation.

If `REVIEWER_PASS` genuinely follows, Director/Integrator still must reconcile the four stacked PRs and current canonical PC0, and only the human may authorize any merge.

**MERGE_READY=false until all those gates.**
