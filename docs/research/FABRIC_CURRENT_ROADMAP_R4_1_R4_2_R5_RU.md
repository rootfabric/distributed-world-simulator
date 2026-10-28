# FABRIC — полная дорожная карта физики и компиляции сложности

Обновление плана: 3 октября 2026. Предыдущая редакция: 20 сентября 2026.
Статусы ниже — датированный срез исследовательской линии, не второй scheduler и не объявление production acceptance. Main-owned registry/catalog, Work Order и действующие gates сохраняют приоритет.

**Новый целевой полигон:** [SHIP-LAB-1 — летающая платформа: сборка, повреждение, ремонт](FABRIC_SHIP_LAB_1_ROADMAP_RU.md). План добавлен; реализация и запуск не заявляются.

## Срез проверенных ссылок и ближайший шаг

```text
MAIN_CONTROL_OBSERVED = bfc335a86153a9f12e03563901d26c3253130d65
RESEARCH_BASE = bb191ec4f610f1f879e48fa104ca3155464bbdc2
RESEARCH_BRANCH = repair/fabric-r4-1-numeric-envelope-diagnostics-r1

R5.0                         CLOSED / merged в research
R5.1                         CLOSED / merged в research, PR #672
R5.2A + T1–T13               bounded research implementations merged
T13.5                        CLOSED / merged в research, PR #708
T14                          exact + review PASS; independent verifier run SUCCESS
T14 product PR #719          OPEN / DRAFT / NOT MERGED на момент среза
T15 / T16                    PLANNED
R5.3 / R5.4 / R5 CLOSE       PLANNED
R6 / SHIP-LAB-1 / SHIP-0..6  PLANNED; не production activation
```

R5.1 merge: `630724d2a73e476d0e6dc430e09050e3957d454a`; точный PR хранит independent review/verifier и ограничение structural/local-refinement scaling. Старое `R5.1 CURRENT` в этой карте устарело и исправлено, а исторические evidence не переписаны.

T13.5 merge: `bb191ec4f610f1f879e48fa104ca3155464bbdc2`.
T14 frozen runtime: `5a65e6d245fda85de50d1cf6c4a551c6240677be`, tree `291048dae0044b28b013be045a05270a9b3e5220`.
T14 exact run `37084267024`; fresh review R2 `5398246338`; independent verifier run `37084679847`, jobs `111092386437` и `111092422186` SUCCESS. Это не объявляет T14 merged/closed; description PR может отставать от реального CI.

Ближайшая последовательность: **T14 closure → T15 local structural divergence / instance fork / selective UNBAKE–ReBAKE → T16 → R5.3**. Ниже сохранены широкие test objectives; статус закрытого T означает только bounded scope его design/evidence, а не выполнение всех возможных физических расширений. Например T12 не доказывает полёт корпуса, а T14 не заменяет физический UNBAKE.

## 1. Исторический фундамент — не реализовывать заново

Это обзор происхождения текущей линии. Исторические exact closures сохраняются в своих документах; данной правкой они не перепроверяются и не повышаются до production acceptance.

| Линия | Наработка и граница |
| --- | --- |
| FABRIC0.1–0.4 | Generic components, inline switch, storage, topology-derived conservation и двунаправленные power maps |
| FABRIC0.5–0.8 | Размерности, nonlinear residuals, nonsmooth relations, hybrid time, события и coupled DAE |
| FABRIC0.9–0.13 | Контактные manifolds, persistent graph/islands, sparse/adaptive event-localized execution |
| FABRIC0.14–0.18 | 6DOF, inertia/friction, multibody/contact/wrench research; reviewed core frontier FABRIC0.18 |
| B0.0 | Source/provenance/validity/invalidation/reconstruction foundation |
| B0.1 | Exact boundary reduction |
| B0.2 A–E | Structural aggregate, mass/COM/inertia, reconstruction, guards, local UNBAKE, topology split/ReBAKE |
| BRIDGE-1 + B0.3 | Physical source lifecycle и contact/wrench BAKE; SYNC reviews связывают ветки |
| B0.4 | Dynamic ROM, reduction/certification, runtime lifecycle |
| B0.5 | Hybrid BAKE и executable authorization |
| BRIDGE-2 | Mixed representation, единственный physical writer и согласованный lifecycle |
| COMPLEX0/1/2 | Разрушение, питание, резервирование, механический отклик, повторное воздействие |
| B0.6 | Adaptive physical fidelity: safety сначала, стоимость потом; hysteresis/recovery |
| BRIDGE-3 | FULL → BAKE → bounded LOCAL UNBAKE → canonical mutation → ReBAKE → restart |
| COMPLEX3 | 5k/20k/100k bounded structural/local-refinement baseline |
| B0.7 | Unseen-machine challenge в ограниченном passive steady generic-power family |
| FABRIC1 / SYNC1 | Объединённая derived composition/lifecycle architecture и freeze |
| BRIDGE-4 | Настоящие Construction/Matter источники, physical proposals и external canonical mutation |
| COMPLEX4 / VIS1 | Реальный канонический механизм и наблюдаемый 3D causal lab |
| AUDIT-R0 → REPAIR-R1 → PHYSICS-R2 → COMPOSITION-R3 | Аудит claim/code, integrity/binding, typed material/geometry laws и bounded coupled dynamic mechanism |
| HOLDOUT-R4 → R4.1 → R4.2 | Проверки обобщения, numeric/diagnostic repair, topology/dynamic unseen holdout |

Источники: `FABRIC0_READ_FIRST_RU.md`, `FABRIC_PHYSICAL_CORE_BAKE_BRIDGE1_SYNC_REVIEW_RU.md`, `FABRIC_BAKE_ROADMAP_RU.md`, `FABRIC_BAKE_B0_6_ADAPTIVE_PHYSICAL_FIDELITY_RU.md`, `FABRIC_BRIDGE3_FULL_BAKE_UNBAKE_FULL_RU.md`, `FABRIC_BAKE_B0_7_UNSEEN_MACHINE_CHALLENGE_RU.md`, `FABRIC1_GENERALIZED_WORLD_FABRIC_RU.md`, `FABRIC_BRIDGE4_CANONICAL_WORLD_FABRIC1_RU.md`, `FABRIC_COMPLEX4_VIS1_PLAYABLE_PHYSICAL_LAB_RU.md`, `FABRIC_COMPLEXITY_CORRECTION_PLAN_RU.md`.

FABRIC0.19 не открывается автоматически: сначала конкретный пример недостающего общего примитива и отдельный Work Order. Старые B0.7/COMPLEX3 не превращаются в новые будущие milestones только из-за повторного описания.

### Неизменяемая история HOLDOUT-R4

```text
FABRIC0.18 / B0.x / BRIDGE-1..3       historical research closures preserved
COMPLEX3 5k/20k/100k                  RESEARCH EXACT CLOSED (bounded baseline)
HOLDOUT-R4 @ e6228a39...              ACCEPTED for bounded fixed-family unseen claim
PR #592                              separate human merge gate; no state promotion here
```

Исторический R4 не отменяется. Его claim ограничен тем, что реально проверено: future-beacon параметры внутри заранее замороженных семейств transport / fixed 6-node electrical graph / fixed 5-node axial mechanics / fixed quartic event family, плюс G2 regressions и independent verifier.

## 2. Главная цель — сложный мир при дешёвой симуляции

FABRIC должен позволять миру быть **качественно сложным**, не заставляя runtime каждый tick пересчитывать всю внутреннюю физику.

```text
canonical / semantic complexity
        ↓ physical compilation
compact executable behavior
        ├─ ports
        ├─ small state vector
        ├─ transfer / constitutive equations
        ├─ validity/error envelope
        └─ refinement guards
```

Микросхема может содержать тысячи или миллионы внутренних элементов, но в обычном режиме исполнять несколько relations и необходимое compact state. Tiny generated executable допустим, если boundary behavior действительно сохраняется. Это derived artifact из canonical/physical структуры, а не device-specific shortcut или второй источник истины.

```text
complex subsystem → BAKE / ROM → cheap simulation
validity exit / hidden event / damage / mode change
        ↓ local UNBAKE / refinement
        ↓ detailed solve where causally needed
        ↓ canonical mutation if required
        ↓ new reduced model / BAKE again
```

Цель — **сохранять причинно значимое поведение при минимальном числе исполняемых степеней свободы**, а не держать все внутренности активными. Camera/cosmetic detail не является физической authority.

## 3. Актуальный путь

```text
historical HOLDOUT-R4 ACCEPTED (bounded)
              ↓
R4.1 NUMERIC + DIAGNOSTIC REPAIR              CLOSED
  finite-output/fail-closed envelope, stable PERF failure shape,
  no matrix_hash masking, unchanged G2/PERF/CLOSE/B0.6 contracts
              ↓ new subject + fresh review/verifier
R4.2 TOPOLOGY + DYNAMIC HOLDOUT               CLOSED
  unseen topology families, variable node/port/active-DOF counts,
  near-singular/unsupported negatives, coupled dynamics,
  canonical mutation/rebake, preregistered randomness, independent oracle
              ↓
SCALE-R5 EXECUTABLE CAMPAIGN                  CURRENT RESEARCH LINE
  ├─ R5.0 Measurement Harness + 5k           CLOSED
  │    scan/hash/solve/reconstruct/alloc/RSS/CPU attribution
  ├─ R5.1 Quantitative Scale 5k/20k/100k      CLOSED (bounded structural scale)
  │    one-time index vs local hot work; explicit global control
  ├─ R5.2 Qualitative Complexity Compression CURRENT
  │    electrical/mechanical/coupled systems → compact boundary/state
  ├─ R5.2A Functional Assembly / BehaviorCapsule   bounded T1 contract merged
  ├─ R5.2B Test Ladder
  │    T1  Boundary Network Box                   MERGED
  │    T2  Logic Adder / Counter                  MERGED
  │    T3  Battery from Cells + Materials         MERGED
  │    T4  Stateful Filter / Thermal Pack         MERGED
  │    T5  Motor / Generator                      MERGED
  │    T6  Power Stage / Switching Compression    MERGED
  │    T7  Gearbox / Mechanical Drive             MERGED
  │    T8  Cooling Unit                          MERGED
  │    T9  Laser Emitter                         MERGED
  │    T10 Laser Cannon Functional Assembly      MERGED
  │    T11 Smart Servo / Closed-loop Drive       MERGED
  │    T12 Matryoshka Ship Subsystem              MERGED; not flight/hull
  │    T13 Shared Compiled Instances             MERGED
  │    T13.5 Shared Families / Parametric Variants MERGED
  │    T14 Observation-Driven Selective Refinement exact/review/verifier green;
  │                                               closure/merge still pending
  │    T15 Local Structural Divergence / Instance Fork / Selective UNBAKE–ReBAKE
  │                                               NEXT AFTER T14 CLOSE
  │    T16 NO_SAFE_BAKE adversarial cases         PLANNED
  ├─ R5.3 Hierarchical BAKE / Recursive ROM       PLANNED
  │    component → module → assembly → machine;
  │    recursive shared execution, local reveal and rebuild of dependencies
  ├─ R5.4 Mixed-Complexity 100k Machine           PLANNED
  │    complex/simple systems, multiple BAKE levels, simultaneous events,
  │    local work and genuinely global causal propagation
  └─ R5 CLOSE                                    PLANNED
       quantitative + qualitative compression together;
       durable predicates and explicit cost/limits
              ↓
INTEGRATION-R6                                  PLANNED / MAIN GATES REQUIRED
  fresh current-main consumer + minimal capability transfer
  SHIP-LAB-1 as planned playable integration acceptance target
  independent review/verifier + human merge gate
              ↓
SHIP-0..SHIP-6                                  PLANNED CAPABILITY TRACK
  canonical bridge → powered platform → wiring/fluids/faults
  → moving interior → damage/repair → docking/survival → two-player persistence
```

`MERGED` в этой схеме означает research-lineage, а не main. R5.1 не доказывает dynamic DAE/ROM scaling; T13.5 не доказывает полное pointer-sharing child runtimes между family; T14 не доказывает detailed physical execution. См. design/evidence каждого этапа.

## 4. Gate rules

- R5.0 и bounded R5.1 закрыты; R5.2 использует тот же measurement contract. Не требовать повторной реализации R5.1 из-за старой надписи CURRENT.
- Large executable SCALE-R5 acceptance требует закрытого R4.2 на repaired subject; это уже достигнутая историческая зависимость, не отменяемая новой картой.
- Do not raise `MAX_NODES`, budgets or tolerances merely to obtain PASS.
- `COMPLEX3` — baseline, не будущий milestone для повторной реализации.
- New product mutations after `e622...` require a new subject and fresh evidence; историческая свежесть Reviewer/Verifier не переносится.
- Revealed R4 cases становятся regressions, не повторным unseen corpus.
- Safety/refinement may expand globally when causality requires it; locality is observed, not forced.
- Масштабируемость — не только число объектов: богатая структура должна давать дешёвое boundary-equivalent execution с измеренной стоимостью.
- Compact code должен быть derived/reproducible/canonical-bound; hard-coded behavior для конкретной демонстрации запрещён.
- Внутренние элементы разворачиваются при validity exit, hidden event, damage, mode transition или физически необходимой наблюдаемости; не каждый tick и не просто от приближения камеры.
- Hierarchical reduction рекурсивна; invalidation/refinement распространяются по зависимости/причинности.
- Fixtures T1–T16 проверяют разные классы compilation/reduction; новая машина не должна требовать kernel special-case.
- Functional block не получает gameplay stats как источник истины: capacity/current/heat и shot/recharge/thermal limits выводятся из components/materials/topology/quality.
- Разрешены prefab labels и bounded characterized-component/material floor. Атомная/квантовая симуляция не требуется.
- Измерять active states/equations, traversals, guard cost, memory, compile/rebuild и amortization. Нулевые leaf traversals не равны нулевой работе или доказанному FPS.
- Hidden detail восстанавливается только из сохранённого/reconstructable state; иначе `NO_SAFE_BAKE`, без выдуманного внутреннего состояния.
- SHIP-LAB-1 не меняет frozen T14, historical evidence, main registry/catalog/lease и не создаёт неявный V0 MVP gate.

## 5. Обязательная R5.2B test ladder — научиться компилировать сложность

Fixtures проходят последовательно. Ниже — целевые классы проверок; точный закрытый floor и отложенные расширения читаются в индивидуальных design/evidence. Закрытие ограниченной реализации не объявляет все более широкие пожелания уже выполненными.

### T1 — Boundary Network Box

```text
100–1000 internal electrical elements → exact/validated reduction
2–8 external ports → small boundary executable
```

FULL/BAKE boundary equivalence, power, invalidation после внутреннего изменения, отсутствие покомпонентного обхода в steady-state.

### T2 — Logic Adder / Counter

Generic gates/wires/registers → small combinational/sequential generated executable. Truth/state equivalence, deterministic event ordering, изменение gate инвалидирует capsule. Специальные Adder/Counter kernel classes не заменяют compiler.

### T3 — Battery from Cells + Materials

Materials + geometry/quality → cells → series/parallel modules → battery → compact charge/temperature/necessary health state + electrical/thermal ports. Derived capacity, voltage, resistance, continuous/peak current, heat, mass и limits. Повреждение ячеек меняет affected topology/characteristics и модель. Фактический T3 floor описан отдельно.

### T4 — Stateful Filter / Thermal Pack

Много energy-storage states → малый dynamic ROM. Transient response, energy/error envelope и validity exit.

### T5 — Motor / Generator

Сложная электромеханическая структура → компактная bidirectional model с electrical/shaft/thermal/mount boundaries и необходимыми states/modes. Разгон, нагрузка, regeneration, stall/heat и обратное влияние нагрузки на источник. Закрытый floor не равен полной тепловой модели всех режимов.

### T6 — Power Stage / Switching Compression

Internal switching → averaged/hybrid executable. Средние токи, мощность, тепло; переход к большей fidelity при значимом ripple/режиме — в пределах утверждённого контракта.

### T7 — Gearbox / Mechanical Drive

Gears/bearings/shafts → compact mechanical relation + inertia/loss/modes. Реакция нагрузки, limits, damage-triggered refinement. Backlash/tribology остаются отдельной fidelity, если не входят в закрытый floor.

### T8 — Cooling Unit

Pump + pipes + radiator + thermal masses → few flow/temperature states. Реальное coupling с Battery/Motor/Laser, не gameplay multiplier; hydraulic/electrical pump assumptions явные.

### T9 — Laser Emitter

Power conditioning/emitter/optics/thermal path → compact emitter behavior. Electrical input, optical output, waste heat, temperature/health limits выводятся из сборки в пределах фактической T9 границы.

### T10 — Laser Cannon Functional Assembly

```text
storage + power stage + emitter + cooling + mount/controller
                         ↓
                functional cannon capsule
```

Shot energy, recharge, sustained behavior, heat и failure limits — следствие subsystems. Не hard-coded `damage=100, cooldown=3`. Фактический T10 optical output не равен реализованному damage target.

### T11 — Smart Servo / Closed-loop Drive

Controller + power stage + motor + gearbox + sensor/load → higher-level capsule. Closed-loop response, disturbance, reverse energy flow и selective opening child module в объявленном floor.

### T12 — Matryoshka Ship Subsystem

```text
cells → battery modules → battery
converter + emitter + cooling → cannon
cannons → bank
bank + power system + drives → ship subsystem
```

Каждый уровень имеет capsule; проблема Cannon #3 не требует без причины раскрыть остальных. **Это функциональная иерархия, не готовые корпус/движители/полёт и не playable ship acceptance.**

### T13 — Many Identical Instances / Shared Compiled Code

1 → 10 → 100 instances. Immutable compiled model/descriptor общий; state/binding независимы. Повреждение одного экземпляра не меняет остальных. Compile savings не равны доказательству real-time 100 ships.

### T13.5 — Shared Families & Parametric Variants

Разные structural families переиспользуют одинаковые compiled subtrees. Compile work масштабируется с unique structural deltas, не с количеством экземпляров. Разделять baseline four-full-family compilation и no-cache per-instance compilation. Закрытый пример: 120 → 42 compile events между family; combined T13+T13.5 no-cache baseline 3000 → 42. Prepared child-runtime pointer sharing между family не объявляется; это downstream R5.3.

### T14 — Observation-Driven Selective Refinement

Один выбранный instance, одно выбранное compiled subtree; другие 99 и sibling regions остаются compact, ancestor может быть MIXED. Snapshot/release/restore, provenance и неизменность физических результатов обязательны. Текущий T14 materializes observation representation над frozen model; actual execute остаётся compact. Это не UNBAKE. Физический sensor может потребовать иной fidelity contract; camera/cosmetic detail не меняет authoritative physics автоматически.

### T15 — Local Structural Divergence / Instance Fork / Selective UNBAKE → ReBAKE

Повредить внутренний element глубокой hierarchy одного экземпляра. Canonical mutation создаёт его структурное расхождение; immutable family model и остальные экземпляры остаются целыми. Fork выполняется для affected subtree, не копированием всех объектов.

```text
machine ROM → affected assembly → affected module detail
→ canonical structural successor / instance fork
→ valid state projection → new module ROM
→ rebuild dependent ancestors
```

Требуются реальное detailed physical execution там, где нужно, сохранение состояния/энергии, stale fencing и continuation после отказа/ремонта. Не подменять проверку disable-mask или только T14 observation manifest. Causal effects на общую шину/нагрузки могут выходить за локальный участок. Платформа SHIP-LAB-1 даёт последующий сквозной пример применения, но не меняет границы уже frozen fixtures.

### T16 — NO_SAFE_BAKE

Unresolved hidden mode, insufficient observability, unreconstructable state, unstable/near-critical regime, unsafe error envelope. Правильный результат — validated FULL/refine или явный unsupported fault, не ложная capsule. Некорректная физическая модель не становится безопасной только потому, что выбрано FULL.

### Общий acceptance для каждого test assembly

```text
canonical structure preserved           YES
capsule derived, not second truth       YES
boundary/state behavior within contract
conservation / energy / event audit     PASS where applicable
steady-state internal traversals        bounded / eliminated
active states/equations                 measured
guard/runtime estimator cost            measured
compile/rebuild cost                     measured
source mutation invalidates artifact    PASS
local refinement where causal           PASS
reconstruction                          justified or NO_SAFE_BAKE
device-specific kernel shortcut          FORBIDDEN
```

## 6. R5.3 / R5.4 / R5 CLOSE

R5.3 обобщает уже доказанные вложенные примеры: recursive composition/sharing, mixed-resolution child execution, valid state transfer и rebuild только зависимых ancestors. Нельзя считать весь R5.3 автоматически закрытым из-за T12 или compiled subtree interning T13.5.

R5.4 объединяет quantitative и qualitative complexity: 100k canonical parts, простые и сложные подсистемы, несколько уровней BAKE, несколько событий и реальные общие зависимости. Нужны как локальное повреждение, так и genuinely global propagation. Дешёвый fixed-boundary пример не заменяет эту проверку.

R5 CLOSE связывает durable predicates, independent evidence и измеренную стоимость. Timing/RSS наблюдения и deterministic correctness различаются; budgets фиксируются до соответствующего executable acceptance. Нельзя обещать игровой FPS по числу формул или assertions.

## 7. Новый прикладной план: SHIP-LAB-1 и корабельные возможности

Полный план, acceptance/fault matrix и границы: [FABRIC_SHIP_LAB_1_ROADMAP_RU.md](FABRIC_SHIP_LAB_1_ROADMAP_RU.md).

```text
P0  Contract / canonical binding / single physical writer
P1  Настоящая сборка и независимые mount/signal/power/matter links
P2  Полёт, силы/моменты, груз, mass/COM/inertia
P3  Потеря управляющей связи → реакция → ремонт → управление
    └─ SHIP-LAB-1.MIN (первый законченный результат)
P4  Питание / подача вещества / перегрузка / перегрев
P5  Отрыв движителя / повреждение и split рамы
P6  Selective UNBAKE → state-preserving repair → safe ReBAKE
P7  Cold restart повреждённой машины + вторая компоновка
P8  Independent physics/graphical/agent acceptance + performance report
    └─ SHIP-LAB-1.CLOSE
```

Дальнейшие capability packages: SHIP-0 canonical bridge; SHIP-1 powered platform; SHIP-2 wiring/fluids/faults; SHIP-3 walkable moving construct; SHIP-4 damage/split/repair; SHIP-5 docking/minimal survival; SHIP-6 shared persistent gameplay. Это не переименование T12–T16 и не автоматическое объявление новых product checkpoints.

Ключевые инварианты: без ресурса нет бесплатной тяги; расположение оборудования влияет на движение; обычный отказ имеет допустимое состояние; guard не равен damage; локальная детализация не обрезает нелокальную причинность; repair не сбрасывает заряд/нагрев/движение; split не дублирует предметы/массу; второй layout работает без platform-specific kernel logic; UI и агент используют настоящие команды, а не scripted поломку.

Исследовательская подготовка возможна отдельно при конкретном Work Order; MIN не требует сначала строить 100k-part ship. Перенос в production остаётся **R6: fresh current-main consumer, minimal capability contract, review/verifier, human merge gate**. Текущее V0 MVP не получает новый обязательный gate из этого плана.

## 8. Current acceptance target

Сначала закрыть T14 на неизменном frozen runtime и опубликовать его durable closure/merge по существующим правилам. Затем T15 → T16 → R5.3 → R5.4 → R5 CLOSE. SHIP-LAB-1 — добавленная цель сквозной проверки и будущий R6 consumer; её executable stages ещё не реализованы. Ни research merge, ни этот план не означают main integration.
