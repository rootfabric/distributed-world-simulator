# FABRIC COMPOSITION-R3 — связанный динамический механизм

Статус: **IN_PROGRESS / RESEARCH_ONLY**. Дата: 7 сентября 2026.

```text
WORK_ORDER = FABRIC-COMPOSITION-R3-WO-001
BRANCH = research/fabric-composition-r3-coupled-mechanism-r1
BASE_HEAD = 2c1802bf0b90c7ca11992cb1c166855f2d92c682
BASE_TREE = 37494670a981cacb65761054e5d0953ffa0e719b
CONTROL_MAIN_OBSERVED = c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f
CONTROL_REGISTRY_GENERATION = 81
PREDECESSOR_VERIFIER_HEAD = c5eb0b2bb5270462490136cf045fe8fa80926689
PREDECESSOR_VERIFIER_RUN = 34111406636
RISK = HIGH
```

Это явно запрошенная пользователем ограниченная research-реализация, не dispatch production checkpoint и не активация дополнительного production runtime worker. Main-owned registry по-прежнему владеет project state; его research milestones advisory. Закрытые R1/R2 subjects и verifier-ветка не изменяются. Main, P7, canonical owners и production scheduler находятся вне scope.

## Design Brief до реализации

R2 компилирует материал и геометрию в размерностные механические и резистивные законы, но не доказывает связанную динамику. R3 должен показать один механизм, где электрическая нагрузка меняет движение, движение меняет ток, solver определяет первый физический отказ, а последствия наступают только после canonical commit.

Выбранная ограниченная грамматика: один поступательный ползун, один или несколько параллельных axial spring/damper supports к неподвижным anchors, series resistive path с конечным сопротивлением источника и нагрузки, один линейный power-conserving gyrator. Коэффициенты springs/resistors берутся из неизменного R2 compiler. Boundary ports и coupler coefficient задаются явно; имена fixtures не являются ветвлением solver. Координата ползуна — малая осевая деформация в метрах; геометрическая ось определяется первым support и все supports обязаны быть коллинеарны. Вращение общей сборки не меняет scalar observables.

```text
m*x'' = gamma*i + F_ext - sum(k*x + c*x')
U_source = R_total*i + gamma*x'
P_electrical_coupler = gamma*x'*i = P_mechanical_coupler
E = m*v^2/2 + sum(k*x^2/2)
dE/dt = U_source*i + F_ext*v - R_total*i^2 - sum(c*v^2)
```

Рассмотрены альтернативы: специализированный motor solver (отклонён), старый strength-as-conductance BRIDGE4 surrogate (отклонён), обязательная state-count ROM для двух динамических состояний (отклонена как недоказанное упрощение). Выбран неизменный общий `Fabric0CoupledHybridDAEV1`: размерностный expression DSL, общий algebraic Newton solve, RK4 и event localization. R3 только компилирует данные в эту грамматику и связывает lifecycle с внешними canonical sources.

BAKE в R3 означает ограниченную **точную алгебраическую элиминацию** `i=(U-gamma*v)/R` с тем же generic integrator, а не сокращение динамических состояний, B0.4 ROM certification или доказательство ускорения. Сертификат проверяет положительное конечное R, power identity, binding и parity. FULL имеет явную algebraic current equation. Unsupported topology должна остаться fail-closed / NO_SAFE_BAKE, без скрытых узлов. R2 bake policy не переписывается.

## Failure и canonical ownership

Каждый активный support получает guard и failure expression из собственного R2 capacity. Первый crossing определяется общим solver; сценарий не передаёт target bond для получения нужного отказа. Early guard не означает damage. Failure останавливает физическое время на localized event и создаёт noncanonical proposal. До внешнего commit движение/источник не продолжаются.

ConstructionConstructStore и ConstructionConstructMutation остаются canonical write path. Physical runtime не пишет в store. Команда проверяет supplied current owner/epoch, exact source revision/checksum и pending proposal. Отказ commit не меняет физическое состояние или ledger. После подтверждённого canonical successor только соответствующий support становится неактивным, модель пересобирается, старый BAKE немедленно неисполняем.

Fracture model R3: энергия удаляемой идеальной пружины целиком поступает в явно наблюдаемый fracture-dissipation sink; x/v непрерывны. Это модель мгновенного идеально диссипативного разрыва, не material fracture propagation. Источник допускает отрицательную мощность (рекуперация); скрытого clamp тока нет.

Owner/epoch задаются извне, не извлекаются из derived capsule. Source commands используют существующую Construction state revision, а не второй authority/revision registry. Тесты обязаны покрыть stale owner, stale revision, denied/duplicate mutation, checksum tampering, missing geometry/material и неверный timestep.

## Allowed paths

```text
scripts/research/fabric_bake0/fabric_composition_r3_*.gd
scripts/research/fabric_bake0/run_composition_r3_*.sh
tests/research/fabric1/fabric_composition_r3_*.gd
scenes/research/fabric_composition_r3_*.tscn
RUN_FABRIC_COMPOSITION_R3_TESTS.sh
.github/workflows/fabric-composition-r3-linux-double.yml
docs/research/FABRIC_COMPOSITION_R3_*.md
validation/fabric-composition-r3-*.json
```

Не изменять historical kernels/fixtures/evidence, main-owned control contracts, Construction/Matter production code, P7, ECO, HOLDOUT-R4 или SCALE-R5. Никаких merge/direct-main/force-push.

## Required predicates

1. R2-derived coefficients и FABRIC0 dimension validation; finite input envelope; no fixture-specific solver.
2. Двусторонняя electrical/mechanical sensitivity с независимым аналитическим или численным reference; timestep refinement и observable numerical energy residual.
3. FULL/BAKE trajectory, current, effort/flow и energy parity; handoff/rebake не создают энергию; старый artifact fenced.
4. Solver-selected first failure identity/time, early guard без damage, canonical commit rejection atomicity, реальный ConstructionStore successor, post-commit physical consequences.
5. Детерминированное исполнение, permutation/rigid transform invariance, restart с независимо поданным current authority и event ledger; fresh-process replay из сохранённых canonical sources/commands.
6. VIS читает тот же physical snapshot: pause, single step, явно размерностные source/load controls, inspector energy/owner/revision/fidelity. UI не содержит solver или прямого BROKEN/ON/OFF.
7. Exact Godot import и R3 suite, неизменные R2/R1 regression; source/log hashes, HEAD/TREE и clean tracked checkout.
8. Отдельная независимая review/verification обязательна для acceptance. Implementer PASS не является CLOSED/ACCEPTED.

## Execution / evidence

Exact engine: `4.7.1.stable.double.custom_build.a13da4feb`, Linux SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

Локальный сетевой git transport в данной сессии возвращает DNS error. Source archive exact R2 получен из verifier artifact `10014609687`; GitHub connector остаётся рабочим каналом read/write. Runtime fallback — repository-owned self-hosted Linux X64 с закреплённым engine hash. Это не основание подменять проверку или просить человека выполнить механическую работу.

Final evidence публикуется отдельно после frozen implementation HEAD. Статус, exact tested subject, оставшиеся gaps и следующая роль должны восстанавливаться из Git без чата. До независимой приёмки HOLDOUT-R4 не объявлять разблокированным.
