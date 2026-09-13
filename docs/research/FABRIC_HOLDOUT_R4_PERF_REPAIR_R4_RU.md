# FABRIC HOLDOUT-R4 — PERF REPAIR R4

## Work Order

```text
work_order = FABRIC-HOLDOUT-R4-PERF-REPAIR-R4
role = IMPLEMENTER
base_head = 4ef109b5ae4727605b469dc3600d4337bf8e8642
base_tree = 5a9450162e261459d6533fd368c36b2b515d91eb
branch = repair/fabric-holdout-r4-perf-r4
status = IN_PROGRESS
```

## Причина открытия

Canonical Linux exact `B0.6-CLOSE` на base subject проходит все семантические stages до `COMPLEX2-PERF`, после чего 500-part case завершается:

```text
COMPLEX2PERF_CASE_BUDGET_EXCEEDED
part_count = 500
total_us = 15176181
budget_us = 12000000
```

Порог является mandatory acceptance gate. Он не повышается и не классифицируется как PASS по историческому baseline failure.

## Цель

Устранить реальную вычислительную избыточность в COMPLEX2 lifecycle/performance path и получить настоящий PASS canonical Linux exact при неизменном бюджете:

```text
500  <= 12_000_000 us
1000 <= 12_000_000 us
2000 <= 12_000_000 us
```

после чего повторно подтвердить `B0.6-CLOSE` и HOLDOUT-R4 G2 на одном exact subject.

## Repair Map

Разрешено изменять только при доказанной необходимости:

- `scripts/research/fabric_bake0/complex2_perf_scaling_v1.gd` — диагностическая фазовая телеметрия / PERF orchestration без ослабления assertions;
- `scripts/research/fabric_bake0/complex2_coupled_motion_v1.gd` — устранение повторной валидации/компиляции только при сохранении public fail-closed contract;
- `scripts/research/fabric_bake0/complex2_settle_rebake_reimpact_v1.gd` — использование заранее валидированного immutable assembly в tight stepping loop;
- профильные tests только для проверки эквивалентности и guards; acceptance budgets менять запрещено.

Запрещено:

- менять `CASE_BUDGET_US` или `LOCAL_REBAKE_BUDGET_US`;
- убирать full-reference comparison;
- уменьшать part counts, settle/reimpact steps или физические нагрузки;
- менять tolerance, acceptance markers или qualification-policy;
- переписывать G1 negative history;
- объявлять Repair R4 / R4 accepted по Implementer self-validation.

## Обязательные проверки

1. phase timing diagnostic на canonical Linux exact;
2. `RUN_FABRIC_COMPLEX2_PERF_TESTS.sh` — PASS на 500/1000/2000;
3. `RUN_FABRIC_COMPLEX2C_TESTS.sh` и `RUN_FABRIC_COMPLEX2E_TESTS.sh` — semantic/hash regression PASS;
4. `RUN_FABRIC_B0_6_CLOSE_TESTS.sh` — PASS, включая PERF и COMPLEX2-CLOSE;
5. `RUN_FABRIC_HOLDOUT_R4_G2_TESTS.sh` — exact PASS;
6. clean tracked source before/after;
7. fresh independent Reviewer/Verifier required after final product mutation.

## Acceptance authority

```text
implementer_self_accept = false
production_freeze_allowed = false
unseen_holdout_allowed = false
checkpoint_accepted = false
```

Этот Work Order разрешает bounded repair и self-validation; он не разрешает merge, production freeze, unseen reveal или R4 acceptance.
