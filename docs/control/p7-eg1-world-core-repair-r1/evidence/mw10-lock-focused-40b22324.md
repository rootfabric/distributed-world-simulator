# MW10 lock-lifecycle focused validation — candidate 40b22324

Deterministic negative/positive control for Work Order
V0-P7-MW10-CROSS-REGION-LOCK-R1. Probe:
`docs/control/p7-eg1-world-core-repair-r1/probes/test_mw10_lock_lifecycle.gd`.

## Baseline (unchanged c14c37c source) — negative control

```text
command: godot --headless --script probes/test_mw10_lock_lifecycle.gd (baseline worktree)
exit: 1 (expected)
{"assertions":16,"failures":["ownerless-grace-fence:stale-removal-must-refuse","ownerless-grace-fence:live-lock-must-survive","atomic-release-retry:attempts-bounded","atomic-release-retry:released-atomically","atomic-release-retry:injection-count"],"test":"mw10_lock_lifecycle","verdict":"FAIL"}
log_sha256: b4f7cadd6f4396e09b1f15e7a9b687dbfa87f29829b128ad3a8c13514d53a7aa
```

Exactly the five predicted causal failures (ownerless grace fence refusals
and atomic-release retry/atomically/injection accounting).

## Candidate (40b22324) — positive control

```text
command: godot --headless --script probes/test_mw10_lock_lifecycle.gd (candidate worktree)
exit: 0
{"assertions":16,"failures":[],"test":"mw10_lock_lifecycle","verdict":"PASS"}
log_sha256: 6b802faa948764a1a504a3a31f6f60067d2268bf8141002ccf5e4f8b5cb4a9cd
```

## Unchanged regression spot checks on the candidate

```text
MW10 cross-region Matter processes: PASS (53 assertions)   [2 runs]
MW9 lock release retry: PASS (12 assertions)
```

Focused evidence only. The complete unchanged world/core suite and the
29-leaf P7 train must still run on the exact final candidate.
