# PROJECT-FOCUS — Historical regression isolation / Repair Map R2

Дата: 2026-09-05. Parent mission: PROJECT-FOCUS-CONTROL-VALIDATION-R1 / PR #547.
Scope: control tests and existing Project Control validation coverage only.

## Exact reproduction and classification

Control subject: `44eacbc8ff573902b91d37222d41f368a8a46af2`.
Tree: `b8d3fbd638ee5de3ff148554f2d6c2a5f24313cc`.
Canonical baseline: `5b4152958624be4e9cc40f2369ce32c4964f65c3`.

The selected Project Control suites completed in run `33956886157`.
Downloaded standard and directional reports both declare overall YELLOW on
canonical main generation 80; V0 has no findings. G/ECO directional critical
findings remain explicitly non-global-blocking. None of these facts accepts P7.

The complete Harness discovery at the frozen subject ran 166 tests and returned
exit 1: 3 failures, 5 errors, 2 skipped live-GitHub-only tests. Baseline comparison
of the two affected historical suites ran 19 tests at canonical main and returned
exit 1: 2 failures, 5 errors. Therefore seven faults predate this control candidate;
the eighth wrongly applies the historical C22 Work Order to the current focus diff.

Observed faults are test-fixture / historical-authority conflation, not runtime
defects: generation-77 R8 is treated as current, an old launcher path is required,
any historical audit event is assumed to cover current main, historical C22 scope
is applied to unrelated current work, and a pre-activation SM1 test incorrectly
assumes the current repository still lacks the already-recorded EG5 repair.

## Canonical fix owners and bounded changes

- `test_h0_control_harness.py`: replay actual registry/catalog/scheduler snapshots
  from R8 epoch base `4a42c2fb6befb386f5c3eb48d9ba070745e25bbb` inside the test only.
  Preserve current schemas and production functions. The isolated branch fixture
  makes this historical replay usable in an exact detached CI checkout without
  inventing or moving Git refs. Add a separate real-current negative test proving
  the old epoch and its simulated dispatch cannot acquire current authority.
  A stale audit event does not cover another main HEAD. Audit the nonempty exact
  historical R8 diff through `ab674669b9a293d898e5ca5983b4918cc685d990`, not an empty
  or unrelated current diff. Preserve risk, scope and freshness assertions.
- `test_v0_p6_acceptance_effective_state.py`: explicitly supply missing activation
  as the pre-activation fixture. Preserve both EG5 evidence-driven positive and
  negative cases and immutable original/addendum checks.
- Existing `.github/workflows/project-control.yml`: use the repository-owned
  duplicate-key rejecting reader, check registered JSON Schemas, include changed
  JSON files, and run full Harness discovery in addition to named suites. No
  production guard, validation threshold, schema, workflow permission or authority
  contract is weakened. No tests are marked skipped by this repair.

## Verification requirements

Pre-commit local discovery after fixture repair: 167 tests, exit 0, 2 existing
live-GitHub-only skips. This is explicitly a working-tree diagnostic, not exact
published-head evidence. Publish the bounded repair, repeat complete discovery on
its exact Git HEAD and run the existing CI with all refs for the two live tests.
Record schemas, duplicate-key scan, command envelopes, standard/directional PC0,
clean tracked checkout, and independent fresh Reviewer/Verifier for that subject.

The local source transport is validation-only PR #548 / helper commit
`96ee3390d2d421d7c1e6d488aeaa61ded87698bb`, run `33957130311`.
It exports the frozen 44eacbc8 subject, not the helper checkout. Export ZIP digest:
`5819851e6e4026ad2665d53900ce7bfce99e31bb834d1bc2c496c4d8d7b55e13`.
Source tar SHA256:
`9453eb77dc1d0eaeda80314e320170c622ba64e0e9cecffbab2e95c97013e768`.
Git HEAD/TREE and clean tracked state were checked after extraction. Required
live fetch/rev-parse commands ran on GitHub Actions; local DNS remains unavailable.
The pinned jsonschema 4.22.0 wheel was exported and installed locally without
substitution. This transport does not grant runtime, review or merge authority.

No existing event, review, evidence, acceptance, epoch or Work Order was rewritten.
Independent Reviewer/Verifier are not replaced by this Implementer diagnostic.
