# G7.0 Full Acceptance — Fix1 required

**Дата:** 2026-08-09
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g7-semantic-field-fabric`

Первый полный Windows gate G7.0 прошёл focused semantic-field contracts и дошёл до общего world/core regression. Единственный blocker проявился в `test_m4_graphical_shared_gameplay_processes.gd`.

```text
A/B graphical                         PASS
A pickup                              PASS
B contention rejection               PASS
foreign inventory permission          PASS
A/B Item Graph checksum convergence   PASS
server report Item Graph assertions   FAIL (4)
```

Диагностика показала race чтения `server.json` во время AtomicJson replacement. Это shared regression-harness defect из upstream G6 и не изменение G7 semantic-field runtime.

Upstream fix записан в `feature/g6-hydrology-fluid-surface-v0`:

```text
tests/runtime/test_m4_graphical_shared_gameplay_processes.gd
validation/g6-post-acceptance-m4-report-race-fix1.json
docs/checkpoints/G6_POST_ACCEPTANCE_M4_REPORT_RACE_FIX1_RU.md
```

После синхронизации current G6 -> G7 требуется повторить `RUN_G7_0_FULL_ACCEPTANCE.ps1`.
