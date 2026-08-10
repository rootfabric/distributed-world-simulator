# T1A.7.1 — Runtime Recovery Snapshot + Restore Contract

**Decision:** ACCEPTED  
**Branch:** `feature/t1a7-runtime-recovery-interest-scale`  
**Accepted runtime head:** `a1d856de348268c45eccfb1c4646720bc4a996db`  
**Control:** `PC0-2026-08-10-R1`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`

## Что принято

T1A.7.1 добавляет recovery canonical Construction runtime через уже существующую M0 transaction/durability foundation, без отдельного T1 repository/coordinator.

```text
Construction runtime state
        ↓
CONSTRUCTION_RUNTIME aggregate
        ↓
ConstructionM0TransactionBridge
        ↓
AggregateAdapterRegistry
        ↓
AggregateTransactionCoordinator
        ↓
AggregateTransactionRepository
```

Persisted checkpoint содержит:

```text
construct_id + construct checksum
ConstructionRuntimeStateStore
runtime ItemOperationLedger
power_tick
battery storage state
validated power execution profile
```

Не являются persisted canonical recovery identity:

```text
peer/session/server routing
presentation identity
camera / interest state
LOD / HLOD
network channel state
```

## FIX1

Первый Windows recovery gate выявил restart-bootstrap defect:

```text
T1A5_T1A4_BOOTSTRAP_FAILED
  -> T1A4_ASSEMBLY_PLAN_FAILED
     -> ATTACH_PART_SOURCE_ALREADY_ATTACHED
```

M0 уже корректно восстанавливал собранный construct, после чего T1A.4 повторно строил исходный assembly plan.

FIX1 сделал reuse persisted T1A.4 composition явным и opt-in только для recovery path:

```text
T1A.4 materialize_bound(..., reuse_existing_m0=false)
T1A.5 default hook -> false
T1A.7 recovery override -> true
```

При reuse обязательно проверяется canonical-json equivalence восстановленного `ConstructSnapshot` с детерминированным source snapshot и наличие исходного assembly operation result. Новый assembly plan на restart не строится.

## Fresh Windows focused acceptance

Tested head:

```text
a1d856de348268c45eccfb1c4646720bc4a996db
```

Results:

```text
T1A.4 interactive fixture binding      PASS 153
C5B affordance runtime contracts       PASS 32
T1A.5 interactive runtime execution    PASS 67
T1A.5 transactional runtime effects    PASS 36
T1A.7 runtime recovery                 PASS 60
focused gate                           PASS
```

Acceptance подтверждает:

- fresh boot не считается recovery;
- runtime checkpoint добавляется в тот же M0 state как четвёртый aggregate;
- restart переиспользует persisted T1A.4 composition без повторного `ATTACH_PART`;
- runtime subjects, operation ledger, power tick и battery state восстанавливаются согласованно;
- replay старой operation не повторяет utility effect;
- stale command не изменяет runtime или battery state;
- второй checkpoint переживает второй restart;
- canonical `ConstructSnapshot` не меняется recovery-механизмом.

## Fresh full world/core regression

На том же runtime head:

```text
RUN_WORLD_REGRESSION_TESTS.ps1
6 PASS / 0 FAIL
lifecycle final state: STOPPED
exit_code: 0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Status dimensions

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

`MAIN_INTEGRATED=false` и `PRODUCTION_READY=false` сохраняются: T1A.7 является stacked development line, а recovery пока использует explicit checkpoint и не заявляет crash-atomic durability каждой runtime-команды.

## Следующий substage

```text
T1A.7.2 — Late-Interest Baseline + Reconnect
```

Цель: клиент, который подключился или вошёл в interest после runtime mutations, должен получить authoritative baseline и сойтись с canonical runtime без broadcast-all и без создания нового global interest identity. Для архитектурного pattern используются уже принятые MW7 session-fence / subscription / bounded replay / snapshot fallback механизмы, но Matter cell identity не переносится в Construction.
