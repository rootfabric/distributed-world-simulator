# Checkpoint v17.4.0 — MW4 Matter Mutations fix2

## Статус

```text
checkpoint: v17.4.0-simulation-mw4-matter-mutations
delivery:   fix2
build_id:   mw4-matter-mutations-fix2
base:       v17.3.0-simulation-mw3-local-meshing / fix2 + MW4 initial + fix1
branch:     feature/mw4-matter-mutations
status:     FUNCTIONALLY VERIFIED; TOPOLOGY METADATA CORRECTED BY FIX3
```

## Результат review fix1

Fix1 полностью устранил performance-блокер:

```text
MW4 focused: FAIL (9 failures / 100 assertions / 2.561 s)
MW3:         7519/7519 PASS
```

Watchdog больше не срабатывает. Новый блокер относится к canonical JSON contract.

## Причина

Focused fixtures и playable laboratory использовали:

```text
energy_budget_j = 1e18 / 1e19
```

Это integer-valued `float`, превышающий максимальное целое, которое безопасно
представляется в IEEE-754 double и canonical JSON:

```text
2^53 - 1 = 9007199254740991
```

`MatterMutationRequest.validate()` корректно отклонял такие DTO:

```text
NON_CANONICAL_JSON_VALUE
$.matter_mutation_request.energy_budget_j:
Integer-valued number exceeds the safe JSON range
```

Вторичные `MISSING_FIELD` возникали потому, что
`create_excavation_request()` fail-closed возвращал пустой словарь.

## Исправление

- все focused energy budgets `1e18`/`1e19` заменены на
  `9000000000000000.0`;
- default `drill_energy_budget_j` лаборатории заменён тем же JSON-safe значением;
- laboratory receiver `maximum_mass_kg = 1e16` также снижен до
  `9000000000000000.0`, поскольку это значение участвует в canonical receiver hash;
- добавлен отрицательный контрактный тест для
  `9007199254740992.0` (`2^53`);
- тест требует `NON_CANONICAL_JSON_VALUE` и точный field path;
- performance, transaction, mass, revision и rollback семантика fix1 не менялись.

## Ожидаемый focused-профиль

```text
MW4 focused: 187 assertions PASS
```

Три новые проверки:

1. unsafe integer-valued energy budget отклонён;
2. error code равен `NON_CANONICAL_JSON_VALUE`;
3. ошибка указывает на `$.matter_mutation_request.energy_budget_j`.

## Фактический independent review

```text
MW4 focused: 187/187 PASS, 10.843 s
MW3:         7519/7519 PASS
MW2:         7470/7470 PASS
MW1:         3685/3685 PASS
MW0:         2011/2011 PASS
A3:          PASS
M6:          10/10 PASS
git diff --check: PASS
```

Первоначальная metadata fix2 ошибочно фиксировала неполную topology.
Корректное значение закреплено поставкой fix3.

## Обязательная independent review

1. MW4 focused завершается до 300 секунд.
2. Итог: `187/187 PASS`.
3. Safe budget `9000000000000000.0` создаёт валидные requests.
4. Unsafe budget `9007199254740992.0` отклоняется с точным кодом и путём.
5. One-cell и cross-brick excavation commit сохраняются.
6. Replay, stale revision, low energy, full receiver и journal rollback проходят.
7. MW3 — `7519/7519 PASS`.
8. MW2 — `7470/7470 PASS`.
9. MW1 — `3685/3685 PASS`.
10. MW0 — `2011/2011 PASS`.
11. A3 — `12/12 PASS`.
12. M6 — `10/10 PASS`.
13. `git diff --check` — PASS.
