# NET-SMOOTH1 R3 slow ITEM — diagnostic-only P1A admission retry

Parent: PR #787 exact HEAD `f64fed2430f1292773d1561f881e5c8a4cc89075`.
No gameplay, M6 writer, schema, ACK gate or contract changes.

On 21 October the independent #787 real Windows GUI verifier reported
3× `r3-slow-item` INCONCLUSIVE: `P1A_WAIT_PRIOR_PERIODIC` transient
reservation refusal while an earlier periodic durable checkpoint occupies the
only writer. The existing `durable_phase()` aborts the test on the first
rejected ITEM command. It does **not** prove a durable state corruption or
application-level server repair.

This isolated branch changes only the test orchestrator and a pure Python
helper. Opt-in `--retry-prior-periodic-admission` is allowed only together with
`--scenario r3-slow-item`, defaults **OFF**. When the exact error code
`P1A_WAIT_PRIOR_PERIODIC` is returned either as an ITEM rejection or a
transport bridge RuntimeError carrying this code, retry **the identical
operation_id and unchanged payload** with backoff, max ~30s response-time
budget. An unrelated error is a hard failure, not an admission retry.
No backpressure rejection counts as committed. `durable-commands.json` and
`phase_results` retain actual durable counts and emit rejection/attempts/wait
evidence. If the gate cannot settle, the test remains INCONCLUSIVE, not PASS.

## Required independent Windows experiment

Fresh checkout of this repair branch on the same Godot SHA, same
Earth+Quaternius assets. Cold import + focused native regression and exact CI,
then:
- 3 runs with R1+R2 enabled, `--scenario r3-slow-item
  --slow-item-writer-ms 1800 --retry-prior-periodic-admission`
  plus the standard NET-SMOOTH1 R3C2/R3C3/R3C21 flags.
- 2 clients must keep moving while the 24 real durable ITEM operations commit.
- Verify 24 committed unique operations, at least 2 canonical command types,
  idempotent duplicate operation_id replay, generation ordering, no false ACK,
  restart parity, and no fatal persistence events.
- Publish actual counts of rejected admission attempts and ms waited. Validate
  server/client trace completeness. The normative analyzer is unchanged:
  expected refusal can still appear as a recorded rejection, never silently
  waive its frame or command-rejection thresholds.
- If retries never commit, investigate whether server's bounded gate actually
  releases the checkpoint writer, instead of hiding the failure with retries.

The repair is not a R3 immutable-projection optimization; keep this PR Draft,
and merge only after independent review and separate Project Control gate.
