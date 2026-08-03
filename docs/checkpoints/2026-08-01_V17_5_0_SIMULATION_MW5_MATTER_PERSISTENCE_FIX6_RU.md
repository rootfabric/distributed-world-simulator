# V17.5.0 — MW5 Matter Persistence fix6

## Статус

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery:   fix6
build_id:   mw5-matter-persistence-fix6
branch:     feature/mw5-matter-persistence
base:       MW5 fix5 candidate
status:     NOT ACCEPTED — TEST WITNESS DEFECT
```

## Независимый результат fix5

```text
MW5 focused: FAIL
6 failures / 128 assertions / 61.724 s
```

Exact binary64 transport для durable DTO работает. Остались два дефекта: тест ожидал неверный LE-hex probe, а межпроцессный `center_m` передавался через decimal `AtomicJson`.

## Исправление

- фактический Godot `PackedByteArray.encode_double(2026174.8885708766)` закреплён как `886179e3beea3e41`;
- packed probe закреплён как `886179e3beea3e41000000000000f03f`;
- worker создаёт checksummed payload `planet_simulator.mw5_process_context.v1`;
- `center_m` кодируется `MatterPersistenceCodec.encode_persistence_json()` и сохраняется как строка `center_transport`;
- recovery декодирует `center_transport` до трёх `TYPE_FLOAT` до canonical query;
- decimal `center_m` в process context запрещён отдельной focused-проверкой.

Durable checkpoint schema, repository protocol, typed checksum-domain и MW0–MW4 не изменены.

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

## Независимый результат fix6

```text
MW5 focused: FAIL
4 failures / 136 assertions / 55.549 s
```

Binary64 persistence и process transport прошли. Блокер находился в acceptance-предпосылке: `fixture["center_m"]` не был подтверждён как vacuum до сохранения. Прямое измерение показало одинаковый SDF до и после восстановления:

```text
before: -0.28383418702205
after:  -0.28383418702205
```

Это доказывает точность recovery, но не существование полости в выбранной точке. Исправление перенесено в fix7: детерминированный positive-SDF witness выбирается после commit и сравнивается до/после restart.
