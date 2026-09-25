# FABRIC R5.2 / T12 — Ship Matryoshka

Статус: IMPLEMENTATION. Research-only; canonical owners — Construction/Matter.
База: T11 merge `70979aaab49bd6413c628f9e98532944a4bd7c74`, tree `467e2dee02bdb2f95b1c85efce32223ef81ed07a`.

## Design Brief / bounded work order

Цель: батарея T3 питает банк из независимых вложенных модулей. Каждый модуль
композирует существующие T10 Cannon, T11 Servo и отдельный T6 servo drive.
Ship → Bank → Turret → Cannon/Servo → существующие дочерние capsules.
Не менять T1–T11, production runtime, main-owned registry или authority contracts.
Новые файлы ограничены T12 research scripts/tests/docs/validation и отдельным workflow.

Выбран safeguarded scalar solve общей DC-шины, а не разряд батареи по заранее
заданной мощности. Все trial evaluations используют исходный caller-owned snapshot;
результат публикуется только после сходимости и проверки всех детей. Ошибка не
возвращает частичный next_state. Canonical mutation в этом исследовании не выполняется.

Вложенные capsules проверяются по внешнему trusted root checksum, каждому child
binding и существующим SourceRevision/Authority/Dependency contracts. Live records
для всего dependency tree поступают от caller; STALE child запрещает старую сборку.
Refinement receipt указывает только изменённый child и зависимые ancestors, а не
принудительное разворачивание sibling modules. Состояния несовместимой схемы не
проецируются автоматически; требуется специализированный canonical projector.

Насос оплачивается батареей через явно идеальный электрогидравлический адаптер
(eta=1). Потери обмотки servo и его T6 drive экспортируются как внешний тепловой
поток, не исчезают и не добавляются повторно в T10 cooling. Батарея сохраняет
собственный thermal state. Замкнутый баланс включает chemistry, stored heat,
servo kinetic energy, ambient/exported heat, optical output и внешнюю работу вала.

Не заявлены: корпус/полёт корабля, damage targets, новая оптическая физика,
CFD, реалистичный pump motor, battery BMS, production integration или новый owner.
Риск: HIGH composition/energy/persistence; независимые Reviewer/Verifier остаются
отдельными ролями. Implementer не объявляет собственную работу принятой.

## Validation plan

Общая батарея + три модуля; reference shared-bus solve; simultaneous activity;
рекуперация; перегрузка и истощение; headroom; atomic failure; snapshot/replay;
внешняя snapshot hash binding; чужой owner; child tamper и stale descendant;
Cannon #3 invalidation / affected path / state-preserving compatible rebuild;
неизменённые T3/T6/T8/T9/T10/T11 regressions; measured iteration/evaluation counts.
Счётчики операций inherited symbolic IR, не замена измерению времени. Все solver
iterations и child calls учитываются отдельно; нулевые leaf traversals не означают
нулевую вычислительную стоимость.
