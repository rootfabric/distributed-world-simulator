# HOLDOUT-R4 G1 — measurement repair 002

Work Order: `FABRIC-HOLDOUT-R4-WO-001 / MEASUREMENT-P1-002`, HIGH. Fresh review `5133896039` of measurement HEAD `9c5ee890d9f770756e37c1d3df84b4f3c1dbd477` found two evaluator defects: `3951325108` (blanket multiport failure even with correct complete observed fields) and `3951325117` (unrelated compile rejection can pass an invalid case).

Это исправление только R4 evaluation/калибровочных тестов. Kernel `fd6e83b35301d7a15e92c55939654f1f95729730`, все 5477 predecessor files, independently revealed G1 input bytes и физические допуски не меняются. Предыдущий exact run 34141668586 и его FAIL сохраняются, а не заменяются новым PASS.

## Repair Map

Owner — `scripts/research/fabric_holdout_r4/holdout.py`, entry `evaluate`, callers main measurement loop и self-authored protocol suite. Probe уже возвращает полный фактический snapshot. Корень первого дефекта — оставшийся ранний `len(ports)>2` запрет после внедрения полного per-edge/per-port oracle. Его удалить: coverage и семантика каждого порта проверяются фактическими `electrical_observables`, KCL и power balance, не числом портов. Действительно отсутствующий readback остаётся FAIL. Это не реализация multiport в frozen R3: настоящий R3 по-прежнему отвергает такой граф при compile.

Корень второго дефекта — ранний negative return до проверки локальной R2 primitive validity и причины отказа. Вычислять invalid domain отдельными независимыми электрическим/механическим oracle, требовать оба R2 success, source immutability и согласованную заранее документированную runtime error category. Для electrically disconnected/floating сети текущая допустимая категория — `R3_CONNECTED_SERIES_PATH_REQUIRED`; parse/input/infrastructure ошибки и обычное `R3_SERIES_PATH_REQUIRED` не являются доказательством правильного rejection. Неизвестная категория для другого invalid domain остаётся fail-closed, а не принимается по совпадению строки family.

## Проверки до freeze нового измерителя

Калибровочные falsifiers: полный корректный multiport readback не отклоняется только за три порта; отсутствие readback и неправильный port current отклоняются; false invalid transport/R2 parse error не PASS; корректная категория electrical invalid с успешными R2 primitives PASS; неожиданный error code FAIL; invalid source mutation FAIL. Старые 20 protocol tests сохраняются.

Повторить все неизменные G1 cases/variants, два fresh процесса, native Godot JSON roundtrip probe и R3/R2/R1 regressions на новом exact measurement HEAD/TREE. Измерительный PASS не является R4 physical PASS; G1 capability/replay FAIL не ремонтируются этой работой. Новая независимая проверка оценивает измеритель, не выдаёт обобщение за выполненное. R4 CLOSED и SCALE-R5 не разрешены.
