# V0 P6 R3 — ретракция ложных claims о завершённости

Дата: 2026-08-24 (UTC+10)

Ветка: `repair/v0-p6-persistence-exactly-once-r1`

Основание: Repair Map `V0-P6-R3-REPAIR-001`, finding
`P6-R-007_FALSE_SOAK_AND_VISUAL_COMPLETION_EVIDENCE`;
WO `V0-P6-R3-WO-001`, предикат
`V0_P6_R3_FALSE_COMPLETION_EVIDENCE_RETRACTED_PASS`.

## Что ретрактируется

История не переписывается (append-only): нижеперечисленные события остаются
в `E2026-08-23-V0-P6-R2` как историческая запись, но их доказательная сила
АННУЛИРУЕТСЯ настоящим документом.

### 1. Событие 0015 — `V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS`

```text
config/control/harness/executions/E2026-08-23-V0-P6-R2/events/V0-P6-R2-WO-001/0015-predicate-v0-p6-thirty-minute-two-client-soak-pass.v1.json
head_sha заявки: 9e0cc74fdab020d35ec52d501c2b15614298c4a7
```

Claim «Predicate V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS durably proven»
ретрактируется полностью: литерального 30-минутного two-client soak в
реальном времени не проводилось. Фактически существовал ускоренный/
симулированный повтор операций (ныне честно переименован в
`REPEAT_IDEMPOTENCE_PASS` — repeat/idempotence, НЕ soak).

### 2. Производное заявление события 0031 — «All 26 required predicates VERIFIED»

```text
config/control/harness/executions/E2026-08-23-V0-P6-R2/events/V0-P6-R2-WO-001/0031-checkpoint-proposed.v1.json
summary: "All 26 required predicates VERIFIED. Checkpoint proposed for acceptance."
```

В части, опирающейся на ретрактируемый soak-предикат и на отсутствующее
MCP visual evidence, заявление «all predicates VERIFIED» недействительно.
Checkpoint proposal R2 считается отозванным; P6 НЕ принят.

### 3. MCP visual evidence (P7–P11)

MCP visual proof для P6 не проводился ни в одной из сессий R1/R2. Любые
упоминания завершённости визуальных проверок P6 недействительны.

## Чем заменяется

Оба литеральных гейта объявлены обязательными в WO `V0-P6-R3-WO-001` и
остаются ОТКРЫТЫМИ до фактического исполнения:

```text
V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME   — PENDING
V0_P6_P7_P11_MCP_VISUAL_EVIDENCE_PASS                — PENDING
```

PASS фиксируется только за реальный прогон exact-head с durable-артефактами
(логи/summary в `artifacts/test-results/…` и/или evidence-документе).
Ускорение времени, симуляция часов и подмена «повтора» на «soak» запрещены
stop-conditions WO.

Дополнительно ретракция не распространяется на core-fix предикаты R3
(`PRIVATE_PERSISTENCE_REMOVED_PASS`, `CANONICAL_OWNER_COMPOSITION_PASS`,
`PENDING_RETRY_FAIL_CLOSED_PASS`, `OPERATION_ID_RETIREMENT_CANNOT_REEXECUTE_PASS`,
`REAL_PROCESS_RESTART_DELEGATED_RECOVERY_PASS`) — они подтверждены свежими
прогонами на ветке R3 (см. `2026-08-24_V0_P6_R3_LOCAL_TEST_SESSION_RU.md`,
16/16 PASS).

## Статус предиката

`V0_P6_R3_FALSE_COMPLETION_EVIDENCE_RETRACTED_PASS` — ЗАКРЫТ настоящим
документом: ложные claims явно аннулированы, заменяющие гейты объявлены
pending без какой-либо имитации их выполнения.
