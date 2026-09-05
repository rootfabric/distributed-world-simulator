# B0.6 — scope, control и post-build critique

## Verdict

`NO_MATERIAL_REFACTOR_REQUIRED` для проверенного research scope после R2/R3.
Это bounded critique текущего восстановления, не вымышленный независимый agent review.

A является единственным safety evaluator; B не расширяет safe prefix. C не создаёт
solver и не меняет canonical source. D хранит только disposable derived capsule.
E адресует существующий source key и публикует один execution slot атомарно.
Возвращаемые descriptors/state/ownership копируются, внешняя мутация DTO не меняет slot.

Цена не переопределяет safety; камера/FPS/OS time не участвуют в решении. Нормализация
JSON integers происходит после validation и не генерирует source revisions/authority epochs.
Повторный authoritative tick с конфликтующим input отклоняется; source/tick regression
и physical-input change без source rebind не принимаются. DORMANT сохраняет causal
responsibility, хотя execution parked. Любая ошибка safety переводит slot в halted.

## Проверенные соседние поверхности

B0.5, B0.4 и B0.2/B0.1/B0.0; BRIDGE-1; BRIDGE-2 ownership, mixed adapter и execution gate;
SYNC4 exact historical recovery; COMPLEX1B powered mixed object; COMPLEX2 A–E/PERF/CLOSE.
Отдельно runner failure paths, JSON disk roundtrip и шесть prerequisite scene parsers.
Полная цепочка исполняется дважды; hashes/scale counters сравниваются машинно.

## Устранённые причины

Rehashed contradictory A witness; JSON integer roundtrip; missing historical SYNC4
packaging; неверный payload TREE в recovery workflow; inherited UTF-8 BOM scenes;
игнорирование tee exit в runner. Fixes внесены в источник ошибки, acceptance не ослаблен.

## Границы и оставшиеся будущие задачи

E измеряет 500/1000/2000 controller/adapter subjects, не 2000 полноразмерных численных
машин. Source certificates поступают от существующего physical owner; checksum не
доказывает физическую истинность входа. Atomicity относится к одному authoritative
research runtime slot, не к новой распределённой транзакции. Диагностический snapshot
сортирует keys; горячие addressed evaluations не делают глобальный scan/rebuild.

BRIDGE-3, произвольная геометрическая full/bake/unbake composition, COMPLEX3,
FABRIC0.19 и P8/P9 production integration не выполняются. Следующая production
promotion требует normal review/verification/merge gates и main-owned authorization.

## Почему не закрывается чужая Harness mission

Main-owned project-control policy 4bc292260708aaede6a2534ad2725148a1dc6467 и harness
policy 38f3d6529e820a597027c6d90c64b368cd6fe90c сохраняют research frontier как отдельную
линию до explicit promotion. Catalog d7ea6e0a4446a0ac3e003035364a7f1833943a34 не содержит
FABRIC/B0.6 checkpoint. Поэтому V0 -Drive/-CloseMission, его acceptance/lease и direct
main write не подменяют research exact closure. Critical watched intersections: 0.
Machine facts: validation/fabric_b0_6/control-applicability.v1.json и scoped audit.
