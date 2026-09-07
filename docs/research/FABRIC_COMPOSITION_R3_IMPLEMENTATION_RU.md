# FABRIC COMPOSITION-R3 — реализация связанного механизма

Статус: **IMPLEMENTED / INDEPENDENT_ACCEPTANCE_PENDING**.

Это implementer report, не independent review и не разрешение merge. Work Order: `FABRIC-COMPOSITION-R3-WO-001`. Исходная ветка R2 и main не изменены.

```text
BRANCH = research/fabric-composition-r3-coupled-mechanism-r1
BASE_HEAD = 2c1802bf0b90c7ca11992cb1c166855f2d92c682
BASE_TREE = 37494670a981cacb65761054e5d0953ffa0e719b
R2_VERIFIER_HEAD = c5eb0b2bb5270462490136cf045fe8fa80926689
R2_VERIFIER_RUN = 34111406636
RISK = HIGH
NEXT_ACTOR = FRESH_INDEPENDENT_REVIEWER
HOLDOUT_R4 = NOT_ACTIVATED
```

Final subject HEAD/TREE определяются Git, а не самоссылкой в этом файле. Для публикации обязательны successful `FABRIC COMPOSITION-R3 Linux Double` на этом exact HEAD, raw logs и evidence manifest. Bootstrap run, экспортировавший approved engine, **не** является проверкой реализации.

## 1. Что исполняется

R3 компилирует уже принятые R2 mechanical/electrical models в неизменный `Fabric0CoupledHybridDAEV1`. Нового integrator, специализированного motor solver, legacy conductance surrogate или canonical authority registry нет.

```text
m * dv/dt = gamma * i + F_external - K*x - C*v
U_source = R_total * i + gamma * v
dx/dt = v

E = m*v^2/2 + K*x^2/2
Delta E + Q_joule + Q_damper + Q_fracture
    = W_source + W_external
```

`K=sum(E*A/L)`, `C=sum(c_element)` и `R_total=sum(rho*L/A)` выводятся из canonical sources. `gamma` — явно заданный коэффициент идеального линейного power coupler; его размерность одновременно N/A и V*s/m. Source/control descriptor хранится в checksummed `ConstructionSnapshot.compiled_facets.composition_r3`, с обычной Construction revision. Это research consumer contract; production activation не заявляется.

Ток FULL читается из фактически решённой algebraic variable, не подменяется аналитическим readback. Snapshot показывает electrical constraint residual, effort/flow, source/external work, Joule/damper/fracture dissipation, x/v, owner binding, revisions, fidelity, силы каждой опоры и pending proposal. Отрицательные ток и source power при рекуперации разрешены.

### Уточнённая область применимости

Один scalar translational slider, до 32 параллельных axial spring/damper supports, неподвижные **коллинеарные опоры с одной стороны** и connected series resistive path с одним source resistor и одним load resistor. Same-side restriction исключает зависимость знака scalar port от canonical ID при выборе опорной оси. Опоры с разных сторон без отдельного ориентированного port contract отвергаются, а не получают произвольную ось.

Материалы и reference temperature — в пределах R2 contract. Capacity меньше `1e-6 N` не допускается: она находится вне принятого численного event envelope. `mass>=1e-6 kg`, `R_total>=1e-9 Ohm`; control magnitudes bounded by `1e6`. Rate-derived step envelope ограничивает RK4; слишком малый допустимый шаг тоже fail-closed. Это идеальные линейные axial elements и идеальный guided slider, не nonlinear rubber, 3D rigid-body/contact, thermal, distributed execution или topology holdout.

## 2. FULL / BAKE

FULL сохраняет algebraic current equation. BAKE выполняет только точную подстановку `i=(U-gamma*v)/R` в тот же dimension-checked DSL. Динамические состояния `x/v` остаются двумя, четыре energy-accounting integrals остаются четырьмя.

Certificate привязан к compiled model, всем actual Construction/Matter sources и independently supplied authority envelope. JSON roundtrip сертификата допустим; rehashed изменение его смысла или старые source/epoch bindings — нет.

На early guard BAKE прекращается в локализованный момент; FULL продолжает остаток шага с теми же состояниями и energy integrals. Guard сам не меняет canonical source. После разгрузки допустим новый BAKE. После canonical mutation старый certificate неисполняем. **State-count reduction, B0.4 ROM certification и performance speedup не заявляются; R2 bake policy не переписана.**

## 3. Физический отказ и единственный canonical writer

Порог проверяет generic hybrid solver отдельно для каждого support и обоих знаков усилия. Первый crossing определяет bond и время. Сценарий не передаёт target bond для получения нужного результата.

На crossing physical time останавливается и появляется proposal. Внешний owner может отказать commit: ConstructionStore, runtime, энергия и journal остаются неизменными. Для успешного commit bridge сначала валидирует successor и готовит новое physical observer state, затем применяет существующий `ConstructionConstructMutation` к staged `ConstructionConstructStore`. Обе стороны публикуются в одном синхронном owner turn без await/частичного commit.

Команды проверяют **exact current store checksum/revision и independently supplied current authority checksum**. Duplicate event, stale source, другой owner/epoch, invalid input, неверный certificate или unsupported shape не обходят границу.

После commit удаляется только фактически broken support. x/v непрерывны. Энергия его пружины явно переносится в `fracture_heat_j`: модель идеально диссипативного мгновенного разрыва, не energy creation и не fracture-propagation model. Проверены два совпавших по времени отказа: второй получает отдельный canonical successor в том же физическом instant, без скрытой оставшейся пружины.

## 4. Независимые от assembler физические ориентиры

Acceptance test независимо вычисляет closed-form damped-oscillator solution, используя объявленные исходные параметры, а не coefficients, прочитанные из compiled model.

Локальные результаты exact Linux double:

| Проверка | Результат |
| --- | --- |
| R3 acceptance | 187 assertions, 0 failures |
| Observer input/snapshot integration | PASS |
| Fresh-process writer / reader | PASS |
| Cold replay before canonical failure commit | PASS |
| Cold replay immediately after commit | PASS |
| PHYSICS-R2 analytical / contract / metamorphic | PASS |
| REPAIR-R1 integrity | PASS, 42 assertions |
| Rendered scene, Xvfb + Mesa llvmpipe | PASS, before/after PNG inspected |

Для t=0.5 s и h=0.0125/0.00625/0.003125 s сумма ошибок x/v:

```text
1.4698049e-7
9.12869e-9
5.6860e-10
```

Energy residual соответственно около `5.6745e-8`, `3.8262e-9`, `2.4784e-10 J`. Уменьшение шага даёт ожидаемую четвёртую степень; FULL/BAKE parity не является единственным oracle.

В default fixture solver выбирает weak support при `t≈0.276443615024909 s`; независимый analytical first-crossing reference совпадает в пределах `2e-7 s`. Fracture sink получает `≈0.07661928473587 J`. Изменение capacity другой опоры меняет выбранный failure path; электрическая и механическая нагрузки дают встречную причинную чувствительность.

## 5. Durable replay — не сохранение derived state

Сохраняются canonical genesis sources и последовательность **принятых** owner commands с before/after store checksums. DAE states/matrices и BAKE capsules не загружаются как truth. Новый процесс заново компилирует источники и воспроизводит историю.

Replay отдельно получает current authoritative Construction store, readonly Matter, current authority и **ожидаемый journal checksum из trusted owner persistence/evidence manifest**. Самоподписанный документ не может удостоверять собственную authority или историю. Hash manifest не является криптографической подписью недоверенного автора; доверие к внешнему owner input остаётся обязательным.

Executable process test создаёт отдельные pre-commit/post-commit checkpoints и final replay package. В новом Godot process воспроизводятся 81 команда и следующие 20 шагов; readback hash точно совпадает с непрерывным запуском. Это bounded research replay, не production crash-consistent storage transaction или checkpoint compaction. Journal ограничен 20,000 commands; transferable ownership ещё не поддерживается.

## 6. Обсерватория

```text
scenes/research/fabric_composition_r3_observatory.tscn
```

Space — пауза/пуск, N — один физический шаг, B — FULL/BAKE. UI sliders задают voltage [V], external force [N], load [Ohm] через revision-fenced canonical commands. Если есть proposal, следующий шаг обращается к canonical bridge с event ID; UI не пишет BROKEN и не имеет собственного solver. Старые storyboard/scenes не изменены.

```bash
export GODOT_BIN="$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64"
export BREAKPOINT_RUNTIME_DISABLED=1
"$GODOT_BIN" --editor --path . --import
"$GODOT_BIN" --path . res://scenes/research/fabric_composition_r3_observatory.tscn
```

Тесты:

```bash
bash RUN_FABRIC_COMPOSITION_R3_TESTS.sh
bash RUN_FABRIC_PHYSICS_R2_TESTS.sh
bash RUN_FABRIC_REPAIR_R1_TESTS.sh
```

Обязательный CI исполняет fresh import, все перечисленные suites, scope/binding gates и fatal-log scan на **self-hosted Linux X64**, только для repository owner. Optional rendered capture выполняется при наличии Xvfb; отсутствие среды явно записывается как NOT_RUN и не называется visual PASS. Local rendered evidence уже получено на exact binary. Production Windows graphical acceptance не заявляется.

## 7. Исправления, найденные во время реализации

1. Новые DTO keys, присвоенные через Dictionary dot syntax, становились StringName и отклонялись canonical serializer. Source adapter теперь создаёт string keys явно; canonical store binding и cold JSON replay проверены.
2. Inspector не должен вычислять FULL current повторно вместо фактического DAE result. Readback использует algebraic variable и отдельный voltage residual.
3. Самого embedded journal checksum недостаточно для доверия к истории: добавлен independently supplied expected checksum; immutable owner sources/authority проверяются отдельно.
4. Valid serialized certificate с integer-valued JSON numbers не должен ложно отвергаться из-за runtime Variant types. Сравнение canonical, не raw Dictionary identity.
5. Godot formatter не поддерживает `%e`: первоначальный observer test печатал PASS, но обязательный fatal-log scan правильно отверг run. Formatter исправлен; чистый observer/render прогнан повторно.
6. Sub-resolution capacity отвергается вместо ложного initial-condition event при нулевой нагрузке.

## 8. Следующая роль / незакрытые claims

Нужны fresh independent reviewer и exact-subject verifier с собственным oracle/negative cases. Implementer не назначает себе эти роли и не повышает CI PASS до независимого verdict. Reviewer должен проверить численные пределы, event localization/initial conditions, atomic publication, authority/source fencing, replay trust boundary и honesty algebraic-only BAKE.

После независимого принятия R3 можно отдельно активировать HOLDOUT-R4 с freeze до reveal. Сейчас HOLDOUT-R4/SCALE-R5/INTEGRATION-R6 **не начаты**, main/P7/control acceptance не менялись, merge не разрешён этим report.
