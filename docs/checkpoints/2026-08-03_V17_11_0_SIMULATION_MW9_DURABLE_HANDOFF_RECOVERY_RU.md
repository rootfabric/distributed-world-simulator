# v17.11.0 — MW9 Durable Distributed Handoff and Crash Recovery

```text
checkpoint: v17.11.0-simulation-mw9-durable-handoff-recovery
build_id:   mw9-durable-distributed-handoff-recovery
base:       v17.10.0-simulation-rl1-matter-summary-pyramid
branch:     feature/mw9-durable-handoff-recovery
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- checksummed durable authority lease и exact fencing token;
- logical-tick renewal, expiry и CAS claim с epoch increment;
- append-only BEGIN/PACKAGE/PREPARED/DECISION/TERMINAL journal;
- canonical package bytes с внутренним checksum binding;
- optional RL1 summary manifest cache hint;
- atomic active/previous repository, межпроцессный commit lock и orphan pending isolation;
- deterministic crash recovery commit/abort;
- fail-closed durable gate и MW8 runtime adapter;
- terminal runtime reconciliation после restart;
- process-kill acceptance для commit-decided и precommit crashes;
- реальная двухпроцессная CAS-гонка expired lease с единственным durable winner.

## Focused topology

```text
contract/runtime focused: 195 assertions
multi-process recovery:     45 assertions
combined:                  240 assertions
```

## Авторская runtime-проверка

```text
MW9 contracts/runtime: 195/195 PASS × 3
MW9 multi-process:      45/45 PASS × 3
MW9 combined:          240/240 PASS × 3
RL1 regression:        245/245 PASS
RL0 regression:         92/92 PASS
MW7 regression:        114/114 PASS, 93.627 s
MW8 regression:        NOT RUN — accepted MW8 patch отсутствует в локальной authoring-базе
```

MW7 завершился с известными shutdown warnings старого runner. Они возникают после успешного маркера и не связаны с MW9.

## Обязательная независимая матрица

```text
MW9 focused:       240/240 PASS
RL1 regression:    245/245 PASS
RL0 regression:     92/92 PASS
MW8 regression:     98/98 PASS
MW7 regression:    114/114 PASS
git diff --check:  PASS
```

Старые MW7 ObjectDB/resource warnings при shutdown остаются известным неблокирующим поведением, если assertion/exit gates проходят.

## Следующий этап

```text
MW10 — Cross-region Matter Transactions
```
