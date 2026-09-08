# Preserved full-regression failure — MW10 cross-region begin race (local Ubuntu)

Subject: `83eb8e2a` (runtime fix head `03c0318d`, tree `f177103a`).
Run: local Ubuntu P7 closure machine, `validate_candidate.py world`,
run id `local-p7-20260907150054`, job `ubuntu-local-p7-world`.

## Observed

Stage 198 of the canonical world/core suite failed:

```text
test_mw10_cross_region_processes
MW10 cross-region Matter processes: FAIL (53 assertions, 2 failures)
  ERROR: Concurrent begin produced zero or multiple winners
  ERROR: Race durable winner differs from worker report
```

All 197 prior stages were green, including the unchanged EG campaign.
The failing pair is the exact `successes == 0` signature: the durable
checkpoint held exactly one begin record with two region reservations at
generation 2 (those assertions passed), but neither race worker reported
`begin_success`, and the durable record did not match the report-selected
"winner".

## Preserved evidence

```text
artifacts/p7-eg1-repair-world/full-world-core.log        (complete suite log)
artifacts/p7-eg1-repair-world/full-world-core.result.json
artifacts/p7-eg1-repair-world/failure.json
artifacts/p7-eg1-repair-world/postflight.json
artifacts/test-results/world-regression-summary.json     (incremental, 198 stages)
```

The scenario directory is deleted by the unchanged test itself before exit,
so the worker reports are not retained; the failure classification below is
derived from the repository source and reproduced deterministically in the
focused lifecycle probe that accompanies the successor Work Order.

## Classification

Not caused by the P7.4 runner-phases fix: `test_mw10_cross_region_processes`
is invoked by the unchanged generic path, and the same test passed all 299
green stages of the d24 CI run and the current CI world campaign. The defect
is a pre-existing timing-sensitive lock-lifecycle hole in
`matter_cross_region_transaction_repository.gd`, exposed once under local
I/O interleaving. 40/40 standalone hammer runs of the identical race worker
scenario produced the normal exactly-one-winner outcome, proving rarity, not
absence: the deterministic causal hole is proven by the focused probe.

Detailed root cause and design: see `REPAIR_MAP_MW10_LOCK_RU.md`.

## Superseded artifact note

`artifacts/p7-eg1-repair-world/failure.json` in the shared local output
directory belonged to the early-exit r2 validation attempt (run
`local-p7-20260907154823`, `MISSING_OR_DUPLICATE_REPORT:mw10-lock-lifecycle`
— the probe identifier typo fixed in commit a52faf8c). It was renamed
`superseded-r2-typo-failure.json` with byte-identical content, and the
world manifest file list was regenerated accordingly. The final r3 run
(`local-p7-20260907155640`) passed with no failure.json.
