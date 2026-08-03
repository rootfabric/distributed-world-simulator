# v17.12.0 — MW10 Cross-region Matter Transactions

```text
checkpoint: v17.12.0-simulation-mw10-cross-region-matter-transactions
build_id:   mw10-cross-region-matter-transactions
base:       v17.11.0-simulation-mw9-durable-handoff-recovery (fix2 ACCEPTED)
branch:     feature/mw10-cross-region-matter-transactions
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Реализовано

- exact MW9 lease/fencing participant contract;
- deterministic sorted multi-region plan;
- distributed per-material mass ledger;
- atomic all-region durable reservations;
- post-reservation authority recheck и automatic abort при race;
- MW9 handoff interlock для reserved regions;
- append-only prepare/decision/commit/rollback journal;
- irreversible global commit decision;
- exact receipt parent/source binding;
- active/previous atomic repository и cross-process lock;
- deterministic crash recovery;
- terminal operation replay;
- global representation invalidation batch только после полного commit;
- durable unpublished/published outbox lifecycle;
- hard-crash и concurrent begin process acceptance.

## Focused topology

```text
contracts/runtime focused: 184 assertions
multi-process recovery:      51 assertions
combined:                   235 assertions
```

## Авторская runtime-проверка

```text
MW10 contracts/runtime: 184/184 PASS × 3
MW10 multi-process:      51/51 PASS × 3
MW10 runner:             PASS (2/2 suites) × 3
MW9 regression:         240/240 PASS
RL1 regression:         245/245 PASS
RL0 regression:          92/92 PASS
MW7 regression:         114/114 PASS, 93.823 s
Godot editor import:    PASS
```

Фактический MW8 patch и `RUN_MW8_MATTER_HANDOFF_TESTS.*` отсутствовали в локальной authoring-базе. Поэтому `MW8 98/98` остаётся обязательным независимым gate на полной принятой композиции `MW7 + MW8 + RL0 fix1 + RL1 + MW9 fix2 + MW10`.

## Обязательная независимая матрица

```text
MW10 focused:       235/235 PASS
MW9 regression:     240/240 PASS
RL1 regression:     245/245 PASS
RL0 regression:      92/92 PASS
MW8 regression:      98/98 PASS
MW7 regression:     114/114 PASS
git diff --check:   PASS
```

Известные ObjectDB/resource warnings старого MW7 runner после успешного маркера остаются неблокирующими и не относятся к MW10.

## Следующий этап

```text
RL2 — Matter Multiresolution Meshing and Cross-level Transitions
```
