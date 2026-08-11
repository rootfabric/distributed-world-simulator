# H0.0 restart-safe control scaffold

`CONTROL_DEVELOPMENT.ps1` is the only public entry point. It supports exactly
one of `-Status`, `-Plan`, or `-Resume`; `-Execute` is deliberately rejected.
The script is PowerShell 5.1 compatible, anchors all paths at `$PSScriptRoot`,
prints readable stage lines first, and leaves one UTF-8 JSON envelope as its
final output line.

The envelope schema is
`validation/harness/control-development-output.schema.v1.json`. Exit `0`
means reconstruction succeeded, even when the reconstructed workflow is
blocked. Stable failure codes are: `2 INVALID_INVOCATION`,
`3 CONTRACT_OR_DEPENDENCY_INVALID`, `4 GIT_STATE_INVALID`,
`5 EXECUTION_STATE_INVALID`, and `6 INTERNAL_ERROR`.

Append-only execution events are authoritative. The Work Order `state` is a
derived snapshot and a mismatch fails with
`WORK_ORDER_SNAPSHOT_STATE_MISMATCH`. Recovery reports the event subject SHA,
the commit containing the event ledger, and the currently checked-out branch
head separately. Main movement blocks continuation unless a recorded audit
permits it; an invalidated epoch always requires refresh.

No command installs dependencies or creates runtime branches. Install the
pinned dependency from `scripts/harness/requirements.txt` in the surrounding
environment, then run `python -m unittest discover -s tests/harness -v`.
