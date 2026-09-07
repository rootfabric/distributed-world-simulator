# FABRIC PHYSICS-R2 — bounded Work Order

Статус: **IMPLEMENTATION_CLOSED / INDEPENDENT_REVIEW_PENDING**. Риск: HIGH (physical semantics / units / compiler boundary).

```text
PREDECESSOR = FABRIC-REPAIR-R1 CLOSED
PREDECESSOR_HEAD = 2c85dfded773392de0b3aa3426cc8b19d98b27eb
PREDECESSOR_TREE = a3e9991765fe82196d6727cd0a3c633024d79b22
CONTROL_MAIN_OBSERVED = c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f
BRANCH = research/fabric-physics-r2-material-geometry-laws-r1
PRE_CLOSURE_EXACT_RUN = 34102321569 SUCCESS
```

Эта работа начата новым ref от exact закрытого R1 subject. Ветка `repair/fabric-repair-r1-integrity-canonical-binding` не изменялась. R2 не является merge/activation в `main` и не переопределяет canonical owner.

## Цель

Закрыть физический долг AUDIT-R0, который R1 намеренно не исправлял: геометрия и материал должны определять физические коэффициенты через явные размерностные законы, а `ConstructionBond.strength_n` должен оставаться capacity отказа, а не суррогатом stiffness/electrical conductance.

R2 даёт малую, проверяемую физическую грамматику для будущего COMPOSITION-R3. Это не новый глобальный solver и не FABRIC2.

## R2-A — versioned material-law contract

Введён явный law contract с доменами:

```text
MECHANICAL_AXIAL
ELECTRICAL_RESISTIVE
```

Поддерживаемые в R2 nominal laws при `293.15 K`:

| material_id | Young's modulus [Pa] | electrical resistivity [ohm*m] |
|---|---:|---:|
| `material/steel` | `2.00e11` | `1.43e-7` |
| `material/aluminum` | `6.90e10` | `2.82e-8` |
| `material/copper` | `1.10e11` | `1.68e-8` |
| `material/rubber` | `1.00e6` | `1.00e13` |

Это **версионированные nominal model constants**, а не заявление о полном поведении реальных материалов при любой температуре/сплаве/частоте. Неизвестный material/domain завершается fail-closed. R2 принимает только чистую одно-компонентную composition; эффективные законы смесей отложены.

Результат: **PASS**.

## R2-B — mechanical axial law

Для `bond_kind = AXIAL_SPRING` реализовано:

```text
L = |x_b - x_a|                        [m]
k = E * A / L                          [N/m]
c = explicit damping_ns_per_m          [N*s/m]
capacity = ConstructionBond.strength_n [N]
```

`A` берётся только из явного `bond.metadata.area_m2`. Нулевая длина, отсутствующая/неположительная площадь, некорректный damping или неизвестный material — fail-closed.

`strength_n` **не участвует** в расчёте stiffness. Изменение stiffness/material/geometry меняет elastic response. Изменение только `strength_n` до damage меняет только failure threshold.

Результат: **PASS**.

## R2-C — electrical resistive law

Для `bond_kind = ELECTRICAL_RESISTOR` реализовано:

```text
L = |x_b - x_a|        [m]
R = rho * L / A        [ohm]
G = 1 / R              [siemens]
```

`rho` берётся из versioned material law, `A` — из `bond.metadata.area_m2`. Механический `strength_n` не входит в `R`/`G`.

Старый R1 BRIDGE4 surrogate, где mechanical strength мог использоваться как generic conductance, **не изменён ради исторической воспроизводимости R1**, но новый R2 model contract выставляет:

```text
legacy_surrogate_compatible = false
```

Будущий COMPOSITION-R3 не должен использовать legacy surrogate как физический R2 entry point.

Результат: **PASS**.

## R2-D — guard != failure

Для mechanical element реализовано:

```text
early_guard = guard_fraction * capacity
load <= early_guard  -> SAFE
load <= capacity     -> REFINE
load >  capacity     -> FAILURE_PROPOSAL
```

`REFINE` не создаёт damage. Разгрузка после guard crossing снова даёт SAFE. Даже `FAILURE_PROPOSAL` не присваивает `BROKEN`: canonical mutation остаётся downstream responsibility.

Проверяемый sweep:

```text
capacity = 100 N
guard = 80%
70 N  -> SAFE
90 N  -> REFINE, damage_committed=false
70 N  -> SAFE after unload
110 N -> FAILURE_PROPOSAL, damage_committed=false
```

Результат: **PASS**.

## R2-E — малые системы / safe FULL fallback

Compiler принимает физически валидные конструкции `2 / 6 / 20` деталей без benchmark-минимума `100+` nodes. R2 не добавляет hidden nodes и не ослабляет validation ради BAKE.

До отдельной сертификации typed R2 reducer model contract намеренно фиксирует:

```text
execution_mode = FULL
bake_certified = false
legacy_surrogate_compatible = false
execution_reason = PHYSICS_R2_TYPED_BAKE_NOT_CERTIFIED
```

Это fail-safe policy: малая физически валидная система исполняется полно, а не подменяется старым surrogate или искусственно раздувается до benchmark-size.

Результат: **PASS**.

## R2-F — metamorphic invariants

Executable acceptance подтверждает:

- global rigid translation не меняет lengths/stiffness/resistance;
- global rigid rotation + translation не меняет физические observables;
- bijective canonical ID permutation/renaming при сохранении topology/geometry не меняет физические observables;
- увеличение length даёт `k ~ 1/L` и `R ~ L`;
- увеличение area даёт `k ~ A` и `R ~ 1/A`;
- смена material меняет коэффициенты по объявленному law;
- изменение `strength_n` не меняет stiffness или resistance до failure.

Результат: **PASS**.

## R2-G — independent physical oracle + dimensions

Acceptance не использует FULL assembler как единственный oracle. Для одного spring и resistive series/parallel fixtures ожидаемые значения вычисляются аналитически из `E*A/L` и `rho*L/A`.

Для линейной статической пружины:

```text
x = F / k
U = 0.5 * k * x^2
W_quasistatic = 0.5 * F * x
```

Проверяется `U == W_quasistatic` с численной tolerance.

Model contract хранит и валидирует SI base-dimension signatures в базисе:

```text
[kg, m, s, A, K, mol, cd]
```

В частности проверяются размеры `Pa`, `N/m`, `N`, `J`, `ohm*m`, `ohm`, `siemens`.

Результат: **PASS**.

## Fixtures

1. One spring: anchor + mass, explicit `A`, explicit damping, capacity 100 N.
2. Load sweep: 70 / 90 / unload 70 / 110 N, guard 80%.
3. Two resistors in series.
4. Two resistors in parallel.
5. Mechanical chains: 2 / 6 / 20 parts.
6. Rigid translation variants.
7. Rigid rotation + translation variants.
8. Canonical ID permutation/renaming variants.
9. Unknown material / mixed composition / unsupported temperature / missing geometry fail-closed fixtures.

## Out of scope

Не входят в PHYSICS-R2:

- COMPOSITION-R3 electromechanical feedback;
- plasticity, fracture propagation, contact/friction, large deformation;
- thermal/hydraulic domains;
- mixture homogenization;
- multidomain energy coupler;
- distributed physics;
- typed BAKE reducer certification;
- 5k/20k/100k scale claims;
- product/main activation;
- изменение canonical Construction/Matter ownership.

## Executable acceptance

Pre-closure exact self-hosted Linux-double run:

```text
RUN = 34102321569
SUBJECT_HEAD = 02313b42903c3daed69a7a1f316df818a1d639bd
RESULT = SUCCESS
fresh import / fatal scan                    PASS
FABRIC-PHYSICS-R2                            PASS
FABRIC-PHYSICS-R2-CONTRACT                   PASS
FABRIC-PHYSICS-R2-METAMORPHIC                PASS
FABRIC-REPAIR-R1 INTEGRITY regression        PASS
HEAD/TREE + source/log SHA256 evidence        CAPTURED
```

Финальный closure HEAD после этой status-фиксации обязан пройти тот же exact workflow; его HEAD/TREE хранится в workflow evidence artifact, а не самоссылкой внутри коммита.

## Closure

```text
R2-A material-law contract                    PASS
R2-B axial geometry/material compilation      PASS
R2-C resistive geometry/material compilation  PASS
R2-D guard/capacity separation                PASS
R2-E 2/6/20 small systems + FULL fallback     PASS
R2-F metamorphic invariants                   PASS
R2-G analytic + energy + SI oracles           PASS
R1 focused regression                         PASS
fresh import / fatal scan                     PASS
implementation status                         CLOSED
independent reviewer acceptance               PENDING
```

Implementer validation **не считается independent reviewer acceptance**. После независимого exact-head принятия следующая дорожка — отдельный bounded `COMPOSITION-R3` Work Order и отдельная ветка; R3 не входит в эту ветку.
