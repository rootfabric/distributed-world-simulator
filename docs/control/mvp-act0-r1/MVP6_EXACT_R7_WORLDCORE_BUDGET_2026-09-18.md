# MVP6 Exact R7 — terminal world/core budget

Validation-only trigger after R6 proved that the 3600-second wrapper watchdog reached the second-to-last discovered world/core test.

- product/runtime code unchanged from the R4 product subject;
- canonical RUN_WORLD_REGRESSION_TESTS.ps1 unchanged;
- internal fail-closed world/core watchdog raised from 3600 to 4500 seconds;
- outer CI job budget raised from 70 to 90 minutes;
- partial world/core evidence remains preserved on timeout/failure;
- world-regression-summary.json is copied into the bounded artifact when available;
- no predicate verification, acceptance, or merge authorization is claimed.
