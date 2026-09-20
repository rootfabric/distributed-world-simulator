# FABRIC — Current Roadmap after HOLDOUT-R4 Audit

Дата: 20 сентября 2026.

## Неизменяемая история

```text
FABRIC0.18 / B0.x / BRIDGE-1..3       historical research closures preserved
COMPLEX3 5k/20k/100k                  RESEARCH EXACT CLOSED (bounded baseline)
HOLDOUT-R4 @ e6228a39...               ACCEPTED for bounded fixed-family unseen claim
PR #592                                OPEN / UNMERGED / separate human gate
```

Исторический R4 не отменяется. Его claim ограничен тем, что реально проверено: future-beacon параметры внутри заранее замороженных семейств transport / fixed 6-node electrical graph / fixed 5-node axial mechanics / fixed quartic event family, плюс G2 regressions и independent verifier.


## Главная цель после R4.2 — сложный мир при дешёвой симуляции

FABRIC должен позволять миру быть **качественно сложным**, не заставляя runtime каждый tick пересчитывать всю внутреннюю физику.

Главный принцип:

```text
canonical / semantic complexity
может быть очень большой
        │
        ▼
physical compilation
        │
        ▼
compact executable behavior
        │
        ├─ ports
        ├─ small state vector
        ├─ transfer / constitutive equations
        ├─ validity envelope
        └─ refinement guards
```

Пример — микросхема:

```text
внутри:
  тысячи / миллионы транзисторов,
  паразитные сопротивления и ёмкости,
  внутренние узлы и режимы

в обычной симуляции:
  НЕ считать каждый транзистор

вместо этого:
  несколько внешних ports
  + компактное dynamic/hybrid state
  + небольшой набор вычислимых equations
  + guards, которые знают, когда этой модели уже недостаточно
```

Практически это может означать, что сложная подсистема компилируется в очень маленький исполняемый artifact — вплоть до нескольких формул или нескольких строк сгенерированного кода — если этого достаточно для сохранения нужного boundary behavior.

Это **не device-specific shortcut** и не второй источник истины. Компактная модель должна быть derived artifact из более богатой canonical/physical структуры, иметь provenance, validity/error envelope и возможность быть отброшенной и пересобранной.

Нормальный режим:

```text
complex subsystem
      ↓
BAKE / ROM / reduced executable
      ↓
cheap simulation
```

Если внутри становится физически важна скрытая детализация:

```text
validity exit / hidden event / damage / mode change
      ↓
local UNBAKE / refinement
      ↓
detailed solve only where needed
      ↓
canonical mutation if required
      ↓
new reduced model
      ↓
BAKE again
```

Цель не состоит в том, чтобы всегда сохранять все внутренние степени свободы активными. Цель — **сохранять причинно значимое поведение при минимальном числе исполняемых степеней свободы**.

## Актуальный путь

```text
historical HOLDOUT-R4 ACCEPTED
              │
              ▼
R4.1 NUMERIC + DIAGNOSTIC REPAIR        ✅ CLOSED
  - finite-output/fail-closed numeric envelope
  - stable PERF failure shape
  - no matrix_hash masking
  - unchanged G2 / PERF / CLOSE / B0.6 contracts
              │
              ▼
NEW SUBJECT FREEZE + fresh review/verifier
              │
              ▼
R4.2 TOPOLOGY + DYNAMIC HOLDOUT          ✅ CLOSED
  - multiple unseen topology families
  - variable node/port/active-DOF counts
  - near-singular + unsupported negatives
  - coupled dynamic trajectory
  - lifecycle/canonical-mutation/rebake continuation
  - preregistered future randomness
  - independent oracle
              │
              ▼
SCALE-R5 EXECUTABLE CAMPAIGN             ← CURRENT
  │
  ├─ R5.0 MEASUREMENT HARNESS + 5k BASELINE      ✅ CLOSED
  │    - разложить стоимость по scan/hash/solve/reconstruct/alloc/RSS/CPU
  │    - зафиксировать корректные измерители до больших оптимизаций
  │
  ├─ R5.1 QUANTITATIVE SCALE                     ← CURRENT
  │    - 5k / 20k / 100k canonical parts
  │    - axes: canonical N / active DOF k / boundary b / events / changed deps
  │    - local event vs genuinely global propagation
  │    - стоимость должна зависеть прежде всего от active/changed region
  │
  ├─ R5.2 QUALITATIVE COMPLEXITY COMPRESSION      ↔ PARALLEL-ELIGIBLE
  │    - сложные electrical / mechanical / coupled subsystems
  │    - много внутренних элементов → мало external ports
  │    - static equivalents + dynamic ROM + hybrid modes
  │    - compact state / equations вместо покомпонентной симуляции
  │    - validity envelope + deterministic error bounds
  │    - NO_SAFE_BAKE, если безопасно сжать нельзя
  │
  ├─ R5.2A FUNCTIONAL ASSEMBLY / BEHAVIOR CAPSULE CONTRACT
  │    - понятные человеку blocks собираются из более мелких physical components
  │    - component/material/quality → derived characteristics
  │    - block → ports + compact state + generated behavior + events + guards
  │    - prefab/name не владеет поведением; behavior выводится из сборки
  │    - разумный floor детализации: не требуется симуляция до атомов
  │
  ├─ R5.2B COMPLEXITY-COMPILATION TEST LADDER
  │    - T1 Boundary Network Box
  │    - T2 Logic Adder / Counter
  │    - T3 Battery from Cells + Materials
  │    - T4 Stateful Filter / Thermal Pack
  │    - T5 Motor / Generator
  │    - T6 Power Stage / Switching Compression
  │    - T7 Gearbox / Mechanical Drive
  │    - T8 Cooling Unit
  │    - T9 Laser Emitter
  │    - T10 Laser Cannon Functional Assembly
  │    - T11 Smart Servo / Closed-loop Drive
  │    - T12 Matryoshka Ship Subsystem
  │    - T13 Many Identical Instances / Shared Compiled Code
  │    - T14 Observation-Driven Refinement
  │    - T15 Local Damage → Local UNBAKE → ReBAKE
  │    - T16 NO_SAFE_BAKE adversarial cases
  │
  ├─ R5.3 HIERARCHICAL BAKE / RECURSIVE ROM
  │    - component → module ROM
  │    - module ROMs → assembly ROM
  │    - assemblies → machine-level ROM
  │    - локальный UNBAKE на любом уровне
  │    - после события rebuild/rebake вверх по иерархии
  │
  ├─ R5.4 MIXED-COMPLEXITY 100k MACHINE
  │    - одновременно простые и очень сложные подсистемы
  │    - несколько уровней BAKE
  │    - local refinement без глобального раздувания FULL
  │    - глобальное расширение допускается только когда его требует causality
  │
  └─ R5 CLOSE
       - 5k / 20k / 100k durable predicates
       - quantitative + qualitative compression доказаны вместе
       - expensive detail active only where physically necessary
              │
              ▼
INTEGRATION-R6
  - fresh current-main consumer
  - minimal capability contract
  - fresh review/verifier
  - human merge gate
```

## Gate rules

- R5.0 measurement harness закрыт. R5.1 — текущий quantitative frontier; R5.2 qualitative complexity compression разрешён параллельно, но обязан использовать R5.0 measurement contract.
- Large executable SCALE-R5 acceptance does not begin until R4.2 is closed on the repaired subject.
- Do not raise `MAX_NODES`, budgets or tolerances merely to obtain PASS.
- `COMPLEX3` is a baseline, not a future milestone to reimplement.
- New product mutations after `e622...` require a new subject and fresh evidence; historical Reviewer/Verifier freshness does not transfer.
- Old revealed R4 cases become regressions only; they can never be called unseen for the new subject.
- Safety/refinement may expand globally when causality requires it; locality is an observed property, not a forced outcome.
- Запрещено считать «масштабируемостью» только уменьшение числа объектов. R5 обязан доказать **компрессию качественной сложности**: богатая внутренняя структура → дешёвое boundary-equivalent execution.
- Компактная модель может быть tiny generated executable (вплоть до нескольких формул/строк кода), но должна быть derived, воспроизводимой и связанной с canonical source; ручной hard-coded behavior для конкретной микросхемы не считается решением.
- Внутренние элементы не обязаны симулироваться каждый tick. Они разворачиваются только при validity exit, скрытом событии, повреждении, mode transition или запросе более высокой fidelity.
- Иерархическая reduction должна быть рекурсивной: subsystem → module → assembly → machine, при этом invalidation/refinement распространяются только настолько далеко, насколько требует зависимость/causality.
- Test assemblies R5.2B являются обязательными falsification fixtures, а не showcase-only demos. Каждый следующий тест должен доказать новый вид compression: elimination, generated logic, state reduction, event compression, bidirectional physical coupling, hierarchy или selective refinement.
- Functional block не получает вручную заданные gameplay stats как источник истины. Например Battery capacity/current/heat должны выводиться из cells/materials/topology/quality; Laser Cannon shot/recharge/thermal limits — из power storage/emitter/optics/cooling/structure.
- Названия `Battery`, `Motor`, `LaserCannon` и т.п. могут быть prefab/assembly labels, но не разрешают kernel special-case вида `LaserCannon.update()` с заранее прописанным поведением.
- Разрешён bounded physical floor: ниже выбранного уровня свойства могут задаваться material/characterized-component contracts. R5 не требует спускаться до атомной/квантовой симуляции.
- Успех compression обязан измерять не только output error, но и реальную исполняемую сложность: active states/equations, internal traversals per tick, guard cost, memory, compile/rebuild cost и amortization.
- Для фиксированного boundary/state контракта рост скрытой внутренней структуры должен по возможности увеличивать compile/rebuild cost, но не линейно увеличивать steady-state tick cost уже скомпилированной capsule.
- Hidden detail может быть восстановлен только из сохранённого/reconstructable state. Если безопасной reconstruction нет, compiler обязан вернуть `NO_SAFE_BAKE`, а не придумывать внутреннее состояние.

## Обязательная R5.2B test ladder — научиться компилировать сложность

Эти fixtures должны проходиться последовательно. Их смысл — не собрать каталог игровых устройств, а доказать разные классы автоматической reduction.

### T1 — Boundary Network Box

```text
100–1000 internal electrical elements
          ↓ exact/validated reduction
2–8 external ports
          ↓
small boundary executable
```

Проверить: FULL/BAKE boundary equivalence, power, invalidation после внутреннего изменения, отсутствие покомпонентного обхода в steady-state.

### T2 — Logic Adder / Counter

Собрать logic graph из generic primitives и получить компактное generated behavior.

```text
gates / wires / registers
        ↓ compile
small combinational/sequential executable
```

Проверить: truth/state equivalence, deterministic event ordering, изменение одного gate инвалидирует старую capsule. Нельзя подменять тест специальным `Adder`/ `Counter` kernel class.

### T3 — Battery from Cells + Materials

```text
materials + cell geometry/quality
        ↓
cells
        ↓
series/parallel modules
        ↓
battery
        ↓ compile
SOC + temperature + health + electrical/thermal ports
```

Derived characteristics: capacity, voltage range, internal resistance, continuous/peak current, heat generation, mass, limits. Повреждение части cells должно локально изменить topology/характеристики и породить новую capsule.

### T4 — Stateful Filter / Thermal Pack

Много внутренних energy-storage states → малый dynamic ROM. Проверить transient response, energy/error envelope и validity exit.

### T5 — Motor / Generator

Сложная электромеханическая структура → компактная bidirectional model:

```text
electrical port + shaft + thermal + mount
state ≈ current / speed / temperature / necessary modes
```

Проверить разгон, нагрузку, generator mode, stall/heat и обратное влияние механической нагрузки на источник питания.

### T6 — Power Stage / Switching Compression

Высокочастотные internal switching events → averaged/hybrid executable. Проверить средние токи/мощность/тепло и переход к более высокой fidelity, когда ripple/режим становятся значимыми.

### T7 — Gearbox / Mechanical Drive

Gears/bearings/shafts → compact mechanical relation + inertia/loss/modes. Проверить обратную реакцию нагрузки, backlash/limit regime и damage-triggered refinement.

### T8 — Cooling Unit

Pump + pipes + radiator + thermal masses → few flow/temperature states. Cooling capsule должна корректно связываться с Battery/Motor/Laser и не быть просто gameplay multiplier.

### T9 — Laser Emitter

Power conditioning + emitter + optics + thermal path → compact emitter behavior. Derived outputs: accepted electrical power, optical output/beam event, waste heat, temperature/health limits.

### T10 — Laser Cannon Functional Assembly

```text
Battery/Capacitor Capsule
        +
Power Stage Capsule
        +
Laser Emitter Capsule
        +
Cooling Capsule
        +
Mount / Controller
        ↓
Laser Cannon Capsule
```

Shot energy, recharge rate, sustained fire rate, heat and failure limits должны быть следствием assembled subsystems. Улучшение cooling меняет sustained behavior; изменение storage/emitter меняет pulse behavior. Никакого hard-coded `damage=100, cooldown=3`.

### T11 — Smart Servo / Closed-loop Drive

Controller + power stage + motor + gearbox + sensor + load → higher-level capsule. Проверить closed-loop response, load disturbance, reverse power flow и selective opening одного дочернего module.

### T12 — Matryoshka Ship Subsystem

```text
cells → battery modules → battery
battery + converter + emitter + cooling → cannon
cannons → weapon bank
weapon bank + power system + drives → ship subsystem
```

Каждый уровень должен иметь собственную capsule. При проблеме Cannon #3 нельзя автоматически раскрывать остальные cannon/battery/ship subsystems.

### T13 — Many Identical Instances

1 → 10 → 100 одинаковых motors/batteries/cannons. Immutable compiled code/descriptor должен переиспользоваться, while state remains per-instance. Повреждение одного экземпляра не инвалидирует остальные.

### T14 — Observation-Driven Refinement

Изменение requested observables может требовать более богатую capsule. Внутренний физический sensor может вызвать refinement; приближение камеры или cosmetic detail — нет.

### T15 — Local Damage → Local UNBAKE → ReBAKE

Повредить внутренний element в глубокой hierarchy. Проверить минимальный causal refinement path:

```text
machine ROM
  ↓ affected assembly only
assembly ROM
  ↓ affected module only
module detail
  ↓ canonical mutation
new module ROM
  ↓
rebuild dependent parents
```

### T16 — NO_SAFE_BAKE

Намеренно создать subsystem, которую текущий reducer не может безопасно сжать: unresolved hidden mode, insufficient observability, unreconstructable state, unstable/near-critical regime, unsafe error envelope. Правильный результат — сохранить FULL/refine, а не выдать красивую, но ложную capsule.

### Общий acceptance для каждого test assembly

```text
canonical structure preserved          YES
capsule derived, not second truth      YES
boundary/state behavior within contract
conservation / energy / event audit    PASS where applicable
steady-state internal traversals       bounded / eliminated
active executable states/equations     explicitly measured
guard/runtime estimator cost           explicitly measured
compile/rebuild cost                    explicitly measured
source mutation invalidates artifact   PASS
local change → local refinement        PASS where causal
reconstruction                         justified or NO_SAFE_BAKE
device-specific kernel shortcut        FORBIDDEN
```

## Current acceptance target

`R4.1`, `R4.2` и `R5.0` закрыты. Текущий active frontier — `R5.1 QUANTITATIVE SCALE`: 5k → 20k → 100k с измерением зависимости стоимости от total N, active DOF, boundary size и changed dependencies. Параллельно разрешён `R5.2 QUALITATIVE COMPLEXITY COMPRESSION`, который должен строиться на том же R5.0 measurement contract.
