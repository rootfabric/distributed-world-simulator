# CONTROL MVP8 R1 — authentic independent Reviewer lineage (Issue #836)

**Scope:** a single historical MVP8 Reviewer event, not FABRIC physics,
not approval to merge, and NOT a general bypass of Git ancestry guards.
Base: independent MVP8 schema-repair PR #834 HEAD
`a5ef36a1716f4d233351b38314fc70355447078c`, itself based on
canonical main `aac301b9a9a89e027f6d99864437eb750a4202ca`.
Repair branch: `repair/control-mvp8-independent-reviewer-provenance-r1`,
separate Draft PR. No direct main write or merge.

## RED: legitimate independent review is a sibling branch

The old `scripts/harness/state_builder.py::_validate_event_git_provenance`
verifies that **every** event `head_sha` is an ancestor of canonical main.
But event #0050 is a `REVIEWER / PREDICATE_VERIFIED` record referencing
`review/v0-mvp8-dc6e7fff-r1` at
`6d1f3fbcbebee31d9be9745f82becc3439de57cc`.
That reviewer commit is intentionally NOT on main. The legacy control gate
returns `EXECUTION_STATE_INVALID / EVENT_SUBJECT_NOT_ANCESTOR:...0050`
on both Windows and Linux after the earlier #834 evidence-map repair.

**Independently checked original Git evidence:**

- Reviewer commit `6d1f3fb...` has exactly one parent — the frozen,
  canonical-reviewed product HEAD
  `dc6e7fffa27d764ea09ded949d50b99a32fa4d9b`, TREE
  `8fc0044ff42ad502e6457593a185465af7d2a825`.
- Reviewer commit TREE `5946f247f66f5dfb083a35b8606f8ac8c6c57700`.
- Diff parent→reviewer is *one newly added file*, not modified runtime:
  `config/control/harness/executions/E2026-09-09-V0-MVP-R1/verifications/MVP8-INDEPENDENT-REVIEW-DC6E7FFF-R1.v1.json`;
  its Git blob is `3759b7caf84ef1e49a894ae2d6b5934e676c15b5`.
- Main already contains that same exact review receipt (same SHA),
  and original event #0050 is untouched (blob `b27cc80072fcb66cb217004ddad35aeb381d37a0`).
- Review DTO declares `FRESH_INDEPENDENT_REVIEWER`, PASS,
  proper product HEAD/TREE, same project epoch/Work Order, empty
  blockers/fixes/gaps, and no merge or human-acceptance claim.

## Narrow GREEN: one exact externally authored Git witness

An exact-pinned `external-role-event-witness.v1.json` under the active epoch
declares precisely ONE review event and one unchanged review receipt. The
modified state builder checks before admitting a non-ancestor subject:

1. Manifest must be tracked, unmodified, correct schema/version/epoch/WO,
   permitted authority and *exactly one witness*.
2. All fields must be present and exact; all paths must be contained under
   the declared event and verifier receipt directories (no wildcards/escape).
3. Immutable event and receipt SHA IDs must match *actual current Git*
   objects (not just JSON hash fields). Original reviewer and product TREE IDs
   must match actual Git commit objects.
4. Reviewer commit must be **exactly one direct child** of the claimed
   product commit, and Git diff-tree must be **exactly one added review file**.
5. Reviewed product must be a real main ancestor. The review receipt in
   the external Reviewer commit and in current branch HEAD must be the
   **same Git blob**, not separate claimed JSON equivalents.
6. Review DTO must confirm reviewer role, PASS, exact epoch/WO/product,
   zero required fixes/blockers/gaps and no merge/human-acceptance.
7. Only after these facts are established does the original all-event
   ancestry check exempt this *exact original event*. Any other
   `head_sha` still has to be a main ancestor; untrusted/unknown
   independent role events remain `EVENT_SUBJECT_NOT_ANCESTOR`.

**Not performed:** merge reviewer branch into main, cherry-pick a reviewer
commit, amend old events, quarantine independent PASS, turn off ancestry
guard globally, rewrite Harness event transition table or schema. Historical
main ledger remains intact.

## Tests / accept gates

- RED: no-witness old event #0050 → expected `EVENT_SUBJECT_NOT_ANCESTOR`.
- GREEN: exact manifest + real Git witness → same event accepted.
- Fail-closed tamper: wrong event blob, wrong review blob, changed
  reviewer parent/tree, false authority/epoch, path wildcard/escape,
  unrelated actor/event type or second added witness → rejected.
- Exact `CONTROL_DEVELOPMENT.ps1 -Status` on Windows and
  `python -m harness.cli status --root` on Linux: capture full JSON
  outcome. Only `exit=0, ok=true` is a *full tooling status* PASS.
- All existing Harness unit tests, pinned `jsonschema==4.22.0`,
  `git diff --check`, frozen scope and unchanged historical Git blobs.
- Full project PC0/directional audit and final Reviewer/Verifier
  **remain independent gates**; successful Status never means PC0 NON_RED
  or permission to merge PR #834/#818/#800/#784.

If subsequent fail-closed state errors appear after #0050 is proven,
report the exact next error without weakening it and prepare a separate
scoped repair.
