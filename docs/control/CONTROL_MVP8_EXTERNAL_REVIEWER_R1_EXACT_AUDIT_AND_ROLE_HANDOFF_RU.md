# CONTROL MVP8 External Reviewer Witness R1 — exact-head acceptance evidence and role handoff

**Frozen repair product:** `a2a8e93f065f9cee8fc8a39eb03df29be322c786`, TREE `e4622f57ec1b86d9193f0675c96f8e67cd9c1d97`.
**Branch:** `repair/control-mvp8-independent-reviewer-provenance-r1`, Draft PR #839, stacked on schema-repair PR #834 HEAD `a5ef36a1716f4d233351b38314fc70355447078c`.
**Canonical main:** `aac301b9a9a89e027f6d99864437eb750a4202ca`.
**Implementer verdict:** `STATUS_TOOLING_RESTORED / CI_3_3_PASS / INDEPENDENT_REVIEW_PENDING / PC0_NOT_CLAIMED / MERGE_READY=false`.

## Root cause and boundaries

Original `CONTROL_DEVELOPMENT.ps1 -Status` on PR #834 was `exit 5`
`EXECUTION_STATE_INVALID / EVENT_SUBJECT_NOT_ANCESTOR:...0050-MVP8-REPAIR-R2-INDEPENDENT-REVIEWER-PASS`.
Real independent reviewer commit `6d1f3fbcbebee31d9be9745f82becc3439de57cc`
was one direct child of product commit `dc6e7fffa27d764ea09ded949d50b99a32fa4d9b`.
It adds exactly one independent PASS review receipt, Git blob
`3759b7caf84ef1e49a894ae2d6b5934e676c15b5`; same blob is canonical-main evidence.
Original immutable event blob `b27cc80072fcb66cb217004ddad35aeb381d37a0`.

New proof allows **only** this Git object/record combination, exact role and
parent, one-file-add diff, exact main/product tree and review receipt; never
rewrites history, never promotes unsigned/missing evidence and never relaxes
unrelated event ancestry. The predecessor #834 evidence-map repair remains
separate and unchanged.

## Fresh published-head CI

[GitHub Actions run 40048516440](https://github.com/rootfabric/distributed-world-simulator/actions/runs/40048516440):
- `scope` job **SUCCESS**, id `120735641481`, exact parent, five changed paths, original event and review Git blobs untouched, `git diff --check`, Python syntax PASS.
- `windows` job **SUCCESS**, id `120735689553`: `6 tests / 0 failures` against the actual Windows checkout, real independent review witness, ancestor RED without witness and GREEN with exact witness, forged epoch/actor/path/parent/tree/blob and second witness rejected. Public `CONTROL_DEVELOPMENT.ps1 -Status`: exit 0, JSON `ok=true`, `CONTROL_MVP8_WINDOWS_FULL_STATUS=PASS`.
- `linux` job **SUCCESS**, id `120735689596`: same 6 targeted tests PASS, `python -m harness.cli status --root ...` exit 0 with JSON `ok=true`, `CONTROL_MVP8_FULL_STATUS=PASS`, full Harness suite **393/393** tests PASS in 207.734 s; `jsonschema==4.22.0` pinned.
- This does not imply `PC0_NON_RED`, independently accepted checkpoint or permission to merge.

## Independent Reviewer work order (fresh separate actor)

Review the exact HEAD/TREE and five-path scope. Recompute first-parent
product SHA + tree of reviewer commit, one-add-only diff, matching exact
Git blob for witness in external commit and current HEAD, unchanged original
event and product ancestry. Challenge event/workorder/role/epoch spoofing,
duplicate witnesses, wildcard/escape, non-reviewer commits, forged PASS,
unrelated non-ancestor events, and remaining main identity guards. Emit
`PASS|FAIL|INSUFFICIENT_EVIDENCE` with cited line numbers and raw evidence
in PR #839, without modifying its product branch.

## Independent Verifier work order (other actor)

Fresh exact checkout. Independently run focused falsifiers on Windows/Linux
or validate raw hosted artifacts with complete integrity, exact
`CONTROL_DEVELOPMENT.ps1 -Status` and `python -m harness.cli status`,
including source branch and SHA. Re-check Harness full regressions and
unchanged genuine reviewer document. Do not infer architecture PC0 from CLI.
Emit separate `VERIFIED|FAIL|INSUFFICIENT_EVIDENCE` to PR #839.

## Integration and prohibition

#834 still Draft and unmerged. #839 is stacked on #834, not directly on main.
Before any human main merge, complete fresh independent role signoffs,
required project PC0/directional audit, and exact post-merge lineage/Status.
Do not merge #839 without its prerequisite #834 and separate human gate.
FABRIC #784/#800/#818 heads untouched; unrelated to this control repair.
