# FABRIC R5.6.1 R2 — Acceptance checkpoint, 2026-10-21

## State

Product HEAD `60f193d6602d2d6ebb62393d3db6633b14623627`; TREE `1a92363e7cc159fef4c42e3443542ebb00a71464`; frozen base `4f301fae461567362d408a51802cc3dde6730999`; PR #784 OPEN/DRAFT. No product changes, no merge, `main` unchanged.

- Fresh official canonical Windows exact **PASS**, user-supplied independent Windows report: R2 3×626/0, scale 255/0, numeric 54/0, COM 52/0, recovery 18/0, R1 203/0, narrow 26/0, BRIDGE-4 49/0, collector v4 PASS, tamper 21/21 reject, own new 95/95 adversarial. Evidence ZIP SHA256 reported `a36d56d10a1e04d309abfd51e70f93088f1c9c704ef87e4eed7c8f7facf18a54`; local Windows ZIP not independently opened here.
- Fresh Linux exact **PASS** executed on exact bundle-restored HEAD with logs and SHA256SUMS 21/21.
- Fresh Linux semantic review **PASS_WITH_NONBLOCKING_FINDINGS**, 51/51 new adversarial GREEN vs same script 38 checks / 8 errors RED on old parent.
- Separate-actor Reviewer and Verifier approval is **not yet independently evidenced** by the same-session Ubuntu worktrees or previous single Windows exact report. GitHub pull-request formal review submissions were empty at checkpoint.

**Disposition:** `TECHNICAL_GATES_PASS; FRESH_SEPARATE_ACTOR_REVIEWER_VERIFIER_PENDING; MERGE_READY=false`. No merge without explicit user authorization.

See individual reports and raw proof in this evidence package.
