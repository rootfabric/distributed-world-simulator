# Distributed World Simulator — Harness Control

**Canonical owner:** `main`  
**Harness revision:** `H0-2026-08-11-R1`

Это короткая точка входа для автономной/полуавтономной разработки.

Полный протокол:

```text
docs/control/DEVELOPMENT_HARNESS_RU.md
```

Machine contracts:

```text
config/control/harness/project-goals.v1.json
config/control/harness/checkpoint-catalog.v1.json
config/control/harness/harness-policy.v1.json
config/control/harness/scheduler-policy.v1.json
config/control/harness/work-order.schema.v1.json
config/control/harness/event.schema.v1.json
config/control/harness/project-epoch.schema.v1.json
```

Главное правило:

```text
open-ended request
      ↓
Director reads main + PC0
      ↓
select declared eligible checkpoint
      ↓
create Project Epoch from exact main SHA
      ↓
issue bounded Work Order
      ↓
worker implements
      ↓
independent verifier
      ↓
PC0 + directional audit
      ↓
checkpoint proposal
      ↓
human gate where required
```

Git является durable memory. Потеря чата не должна мешать `Resume`.

Текущий pilot override:

```text
H0.1 CLOSED-LOOP C22 PILOT
        +
C22 SOURCE_ACCEPTED_MERGE_READY
```

До H0.1 допускается не более одного автономного runtime worker. G8.6/CH9.6 могут ждать как HUMAN_OBSERVATION work orders; R3 analysis может идти параллельно без promotion.

Human approval обязателен для runtime merge, TS0.4 activation, architecture promotion, foundation ownership transfer и новых global foundations.
