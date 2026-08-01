# V17.5.0 — MW5 Matter Persistence fix7

## Статус

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery:   fix7
build_id:   mw5-matter-persistence-fix7
branch:     feature/mw5-matter-persistence
base:       MW5 fix6 candidate
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Независимый результат fix6

```text
MW5 focused: FAIL
4 failures / 136 assertions / 55.549 s
```

Durable checkpoint, exact binary64 DTO transport и process context работали. Ошибка была в тесте: геометрический `fixture["center_m"]` не был доказан как vacuum до сохранения. Его SDF одинаково восстанавливался как `-0.28383418702205` до и после restart.

## Исправление

- после committed mutation helper сканирует interior lattice всех `changed_bricks`;
- кандидаты обязаны иметь `occupancy_ratio = 0` и `signed_distance_m > 0`;
- выбор детерминирован: сначала максимальный отступ от cell boundary, затем максимальный SDF, затем стабильный `address_id/index`;
- выбранная позиция повторно подтверждается `MatterContinuousQueryService` сразу после mutation;
- same-process recovery сравнивает SDF witness до/после restore точным `==` и только затем требует `> 0`;
- process worker сохраняет `position_m` и pre-save `signed_distance_m` в exact payload `planet_simulator.mw5_process_witness.v1`;
- recovery worker требует точного равенства SDF и положительного значения до успешного exit code;
- старые `center_m` и `center_transport` в process context запрещены focused-проверкой.

Durable checkpoint schema, repository publication, generation chain и binary64 transport schema не изменены.

## Требуемая regression-матрица

```text
MW5 focused:     PASS до watchdog
MW4 regression:  187/187 PASS
MW3 regression:  7519/7519 PASS
MW2 regression:  7470/7470 PASS
MW1 regression:  3685/3685 PASS
MW0 regression:  2011/2011 PASS
A3 regression:   PASS
M6 regression:   10/10 PASS
git diff --check: PASS
```
