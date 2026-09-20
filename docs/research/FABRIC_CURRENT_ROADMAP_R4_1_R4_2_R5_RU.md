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
  ├─ R5.0 MEASUREMENT HARNESS + 5k BASELINE
  │    - разложить стоимость по scan/hash/solve/reconstruct/alloc/RSS/CPU
  │    - зафиксировать корректные измерители до больших оптимизаций
  │
  ├─ R5.1 QUANTITATIVE SCALE
  │    - 5k / 20k / 100k canonical parts
  │    - axes: canonical N / active DOF k / boundary b / events / changed deps
  │    - local event vs genuinely global propagation
  │    - стоимость должна зависеть прежде всего от active/changed region
  │
  ├─ R5.2 QUALITATIVE COMPLEXITY COMPRESSION
  │    - сложные electrical / mechanical / coupled subsystems
  │    - много внутренних элементов → мало external ports
  │    - static equivalents + dynamic ROM + hybrid modes
  │    - compact state / equations вместо покомпонентной симуляции
  │    - validity envelope + deterministic error bounds
  │    - NO_SAFE_BAKE, если безопасно сжать нельзя
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

- R5.0 measurement harness идёт первым; после него количественное и качественное scaling развиваются как одна программа, а не как независимые оптимизации.
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

## Current acceptance target

`R4.1` и `R4.2` закрыты на frozen evidence. Текущий research stage — `SCALE-R5`, причём его цель двойная: (1) количественный масштаб 5k/20k/100k и (2) качественная компрессия сложности, когда сложные подсистемы исполняются как компактные boundary-equivalent модели и разворачиваются в детали только когда это физически необходимо.
