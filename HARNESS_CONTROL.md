# Distributed World Simulator — Harness Control

**Canonical owner:** `main`  
**Harness revision:** `H0-2026-08-11-R1`  
**Review layer:** `H0-REVIEW-2026-08-11-R1`

Это короткая точка входа для автономной/полуавтономной разработки.

Полные протоколы:

```text
docs/control/DEVELOPMENT_HARNESS_RU.md
docs/control/HARNESS_REVIEW_AND_EVIDENCE_RU.md
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
config/control/harness/risk-policy.v1.json
config/control/harness/review-policy.v1.json
config/control/harness/repair-doctrine.v1.json
config/control/harness/evidence-map.schema.v1.json
config/control/harness/human-attention.schema.v1.json
```

Главное правило:

```text
open-ended request
      ↓
Director reads main + PC0
      ↓
select declared eligible checkpoint
      ↓
classify risk / prepare Design Brief when required
      ↓
create Project Epoch from exact main SHA
      ↓
issue bounded Work Order
      ↓
worker implements
      ↓
post-build critique when required
      ↓
Evidence Map
      ↓
independent Reviewer + Verifier
      ↓
PC0 + directional audit
      ↓
checkpoint proposal
      ↓
human gate only for real exception/approval
```

Git является durable memory. Потеря чата не должна мешать `Resume`.

Управляющая модель review:

```text
COMMITS          = recovery units
CHECKPOINTS      = control units
EVIDENCE MAPS    = review units
EXCEPTIONS       = human attention units
```

Человеку не должен передаваться поток agent commits. Director обязан сжимать работу до evidence packages и Human Attention Queue.

Risk routing:

```text
LOW      → Implementer + Verifier
MEDIUM   → Implementer + Reviewer + Verifier
HIGH     → Implementer + Reviewer + Verifier + Director
CRITICAL → Implementer + Reviewer + Verifier + Director + Human
```

`FIX_REQUIRED` для MEDIUM+ требует Repair Map перед следующим non-trivial fix. Reviewer имеет verdict только `PASS`, `FAIL` или `INSUFFICIENT_EVIDENCE`; недостающее доказательство нельзя заменять догадкой.

Runtime checkpoint review должен быть exact-head fresh:

```text
reviewed HEAD == evidence HEAD == tested runtime HEAD
```

Текущая pilot-последовательность:

```text
H0.0 RESTART-SAFE HARNESS SCAFFOLD
        ↓
Status / Plan / Resume
state reducer
schema validation
review/evidence contract validation
epoch invalidation detection
Git-only recovery fixture
NO runtime branch creation
        ↓
H0_0_SCAFFOLD_READY
        ↓
H0.1 CLOSED-LOOP C22 PILOT
        +
C22 SOURCE_ACCEPTED_MERGE_READY
```

До `H0_0_SCAFFOLD_READY` автономных runtime workers быть не должно. На H0.1 разрешён максимум один автономный runtime worker. На H0.1 уже обязательны risk classification, Evidence Map, independent Reviewer, post-build critique и exact-head review freshness.

G8.6/CH9.6 могут ждать как HUMAN_OBSERVATION work orders; R3 analysis может идти параллельно без promotion.

Human approval обязателен для runtime merge, TS0.4 activation, architecture promotion, foundation ownership transfer и новых global foundations. Дополнительные human decisions появляются только как явные Human Attention items.
