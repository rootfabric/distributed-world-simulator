# FABRIC HOLDOUT-R4 — G1, проверка обобщения без подгонки

Статус: **PREREGISTERED / CHALLENGE_NOT_REVEALED**. Work Order `FABRIC-HOLDOUT-R4-WO-001`. Risk: HIGH. Research/source only; main checkpoint, production activation и merge не заявляются.

## Неизменный предмет опыта

```text
BRANCH = research/fabric-holdout-r4-frozen-generalization-r1
SUBJECT_HEAD = fd6e83b35301d7a15e92c55939654f1f95729730
SUBJECT_TREE = 314330d717db059cd9b9db32c5d6150097e1f2c3
R3_CLOSURE_HEAD = c9176fe0073b4093afe23d14f21a4c7e47bba106
CONTROL_MAIN = c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f
CONTROL_REGISTRY_GENERATION = 81
FREEZE_GENERATION = G1
```

Вся существующая tracked source tree R3 заморожена: compiler, material laws, runtime, event adapter, generic FABRIC0 solver, reduction policy, canonical contracts и старые тесты. R4 может только добавлять собственные проверки/данные/runner/evidence. Любое изменение существующего runtime после reveal аннулирует G1; исправление требует отдельной generation с новым независимым holdout. Старый FAIL сохраняется.

## Design Brief и критерий успеха до reveal

Основание: `FABRIC_COMPLEXITY_CORRECTION_PLAN_RU.md`, раздел HOLDOUT-R4, и F07 аудита. Требуются действительно разные семейства, а не seeds одного генератора: малые механизмы; последовательные и разветвлённые цепи; мост/контур; переменное число boundary ports; почти вырожденный физически корректный случай; допустимый FULL при отказе BAKE; некорректная/недоопределённая физика.

Проверяются две разные гипотезы:

1. **R3_CONTRACT**: поддерживаемая R3 грамматика сохраняет корректность и fail-closed поведение.
2. **R4_GENERALIZATION**: общий Construction/Matter путь исполняет физически корректные новые topology/port families из уже принятых R2 локальных примитивов.

R3 сейчас явно ограничен одним guided scalar slider, same-side parallel supports и одной series resistive chain. Если корректный мост/ветвление/несколько mobile masses не исполняются, это **capability FAIL R4**, а не автоматически R3 runtime bug и не успешный отрицательный тест. Нельзя после reveal объявить эти обязательные families out-of-scope ради зелёного R4. Только физически некорректные inputs имеют ожидаемый REJECT.

Измерения: фактическая compile/initialize outcome, точный error code, canonical source validation, физические x/v/i и energy balance, FULL/BAKE observables, источник first failure identity/time, source revisions/checksums, rejection atomicity и cold replay. Отдельно считаются семьи, случаи, metamorphic варианты и assertions. Нулевое число кейсов/семейств никогда не PASS. Safety rejection не равен supported FULL. Не заявлять speedup/state reduction/SCALE-R5.

## Публичный interchange для независимого автора

Автор holdout — отдельный внешний контекст после публикации этого freeze. Его полный ответ сохраняется с GitHub identity/comment/SHA256; implementer не выдаёт свои calibration cases за independent holdout. Нужны конкретные числа и графы, не готовая failure sequence и не device-specific solver.

JSON bundle имеет поля `schema: "fabric.holdout_r4.cases.v1"`, `cases: [...]`. Каждый case содержит:

```text
id: unique nonempty ASCII identifier
family: nonempty family name
expectation: PHYSICS | REJECT_INVALID | FULL_ONLY
mechanical_nodes: array of [id, x_in_length_unit, mass_kg, anchored_bool]
springs: array of [id, a, b, stiffness_N_per_m, damping_Ns_per_m, capacity_N]
electrical_nodes: array of [id, x_in_length_unit]
resistors: array of [id, a, b, resistance_ohm, role]
  role = SOURCE_RESISTANCE | LOAD_RESISTANCE | WIRE
ports: dictionary node_id -> voltage_V (2 or more prescribed potentials)
coupler_node: mechanical node receiving electromechanical force
coupling: positive coefficient N/A = V*s/m
external_force_n: force at coupler node
length_unit: m | cm | mm
material_mechanical: material/rubber | material/steel | material/aluminum | material/copper
material_electrical: material/copper | material/aluminum | material/steel | material/rubber
guard_fraction: (0,1)
dt_s: [1e-7, 0.02]
steps: integer [1,500]
```

Все nodes/edges задаются явно. Нет topology generator, скрытых дополнительных nodes, bridge-to-series conversion или подмены currents. Engineering K/R переводятся только в площади реальных canonical bonds: `A=k*L/E`, `A=rho*L/R`, по зафиксированной R2 material law. Разбор SI единиц происходит на входе; runtime по-прежнему получает SI. Canonical constructors — существующие Part/Bond/Snapshot/Composition/MaterialBatch; fixture R3 не используется для создания новых topology.

Два ports задают обычную положительную/нулевую клемму; R3 scalar source voltage может представлять только их разность. Для >2 ports нельзя молча отбросить независимый boundary input: отсутствие port coverage означает capability FAIL даже если инициализация вернула success. Multiport oracle решает каждую заданную клемму отдельно. Механический oracle использует коллинеарные scalar nodal displacements и fixed anchors; ориентированная ось задаётся возрастанием координаты входных данных.

## Независимые физические ориентиры и допуски

Reference не читает compiled coefficients/capsules и не вызывает FABRIC numerical solver. Для резисторов — nodal Kirchhoff matrix из исходных R, рациональная линейная алгебра; KCL, power sum и входная проводимость. Для one-slider/two-port — аналитическое решение линейного damped oscillator с `R_equiv` независимого network oracle и нулевыми x/v. Для multi-mass — матрица упругости/initial acceleration и проверка существования конечного решения; отсутствие результата runtime всё равно FAIL. Недоопределённый floating component отдельно REJECT_INVALID.

До reveal фиксируются допуски: `abs(x_error), abs(v_error), abs(i_error) <= 1e-5 + 1e-5*abs(reference)`; normalized energy residual `<= 1e-5`; FULL/BAKE parity `<=1e-8 + 1e-8*abs(reference)`; first crossing time `<=1e-4 s` относительно независимой локализации, когда оно проверяется. Отказ dt внутри публичного envelope — наблюдаемый отказ, не автоматический PASS. Уменьшение dt в metamorphic проверке — отдельный измеренный вариант, не замена провалившегося исходного кейса.

Metamorphic operator library: перестановка входных списков, полное переименование IDs, общий перенос/поворот с сохранением ориентированного scalar port, SI unit roundtrip, эквивалентное разделение WIRE на два последовательных участка и parallel spring decomposition, заранее фиксированное геометрическое масштабирование с ожидаемым изменением k/R. Эти операции применяются к данным, не к runtime. Структурно разные авторские кейсы остаются отдельными от metamorphic вариантов.

## Разрешённые пути и исполнение

```text
docs/research/FABRIC_HOLDOUT_R4_*.md
config/research/fabric-holdout-r4-*.json
scripts/research/fabric_holdout_r4/**
tests/research/fabric1/fabric_holdout_r4_*
validation/fabric-holdout-r4-*.json
RUN_FABRIC_HOLDOUT_R4_TESTS.sh
.github/workflows/fabric-holdout-r4-linux-double.yml
```

Старые R1/R2/R3, main-owned registry/harness, production owners и чужие workflows не менять. No merge, force-push, branch deletion, HOLDOUT post-reveal tuning, SCALE-R5 или INTEGRATION-R6.

Exact engine `4.7.1.stable.double.custom_build.a13da4feb`, Linux SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`. Fresh import обязателен. Каждый процесс bounded, stdout/stderr/exit/hash сохраняются; runner fail-closed при parse error или отсутствии непустого машинного результата. Frozen source tree сверяется до/после. Calibration/protocol tests отделены от HOLDOUT outcome. R3/R2/R1 regression выполняется без изменения.

Raw challenge, normalized canonical sources, all outcomes (включая FAIL/UNSUPPORTED), commands, exact evaluated HEAD/TREE, hashes и итоговый verdict хранятся в Git/evidence. Два fresh процесса должны дать одинаковый семантический digest. `EXPERIMENT_COMPLETED_FAIL` — честный научный результат, но не `HOLDOUT-R4 CLOSED/PASS` и не разрешение SCALE-R5. Для CLOSED требуются все обязательные physical families PASS, независимое review/evidence verification и source-scope audit. Отсутствие independent challenge data означает INCOMPLETE, не PASS.
