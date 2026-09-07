# FABRIC PHYSICS-R2 — bounded Work Order

Статус: **IN_PROGRESS**. Риск: HIGH (physical semantics / units / compiler boundary).

```text
PREDECESSOR = FABRIC-REPAIR-R1 CLOSED
PREDECESSOR_HEAD = 2c85dfded773392de0b3aa3426cc8b19d98b27eb
PREDECESSOR_TREE = a3e9991765fe82196d6727cd0a3c633024d79b22
CONTROL_MAIN_OBSERVED = c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f
BRANCH = research/fabric-physics-r2-material-geometry-laws-r1
```

Эта работа начинается новым ref от exact закрытого R1 subject. Ветка `repair/fabric-repair-r1-integrity-canonical-binding` не изменяется. R2 не является merge/activation в `main` и не переопределяет canonical owner.

## Цель

Закрыть физический долг AUDIT-R0, который R1 намеренно не исправлял: геометрия и материал должны определять физические коэффициенты через явные размерностные законы, а `ConstructionBond.strength_n` должен оставаться capacity отказа, а не суррогатом stiffness/electrical conductance.

R2 должен дать малую, проверяемую физическую грамматику, которую затем сможет использовать COMPOSITION-R3. Это не новый глобальный solver и не FABRIC2.

## Bounded scope

### R2-A — versioned material-law contract

Вводится явный law contract с доменами:

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

Это **версионированные nominal model constants**, а не заявление о полном поведении реальных материалов при любой температуре/сплаве/частоте. Неизвестный material/domain обязан завершаться fail-closed. R2 принимает только чистую одно-компонентную composition; эффективные законы смесей откладываются.

### R2-B — mechanical axial law

Для `bond_kind = AXIAL_SPRING`:

```text
L = |x_b - x_a|                       [m]
k = E * A / L                         [N/m]
c = explicit damping_ns_per_m         [N*s/m]
capacity = ConstructionBond.strength_n [N]
```

`A` берётся только из явного `bond.metadata.area_m2`. Нулевая длина, отсутствующая/неположительная площадь, некорректный damping или неизвестный material — fail-closed.

`strength_n` **не участвует** в расчёте stiffness. Изменение stiffness/material/geometry должно менять elastic response. Изменение только `strength_n` до damage должно менять только failure threshold.

### R2-C — electrical resistive law

Для `bond_kind = ELECTRICAL_RESISTOR`:

```text
L = |x_b - x_a|        [m]
R = rho * L / A        [ohm]
G = 1 / R              [siemens]
```

`rho` берётся из versioned material law, `A` — из `bond.metadata.area_m2`. Механический `strength_n` не входит в `R`/`G`.

### R2-D — guard != failure

Для mechanical element:

```text
early_guard = guard_fraction * capacity
load <= early_guard  -> SAFE
load <= capacity     -> REFINE
load >  capacity     -> FAILURE_PROPOSAL
```

`REFINE` не создаёт damage. Разгрузка после guard crossing снова даёт SAFE. Canonical mutation при реальном failure остаётся downstream responsibility; R2 не присваивает `BROKEN` напрямую.

### R2-E — малые системы / FULL fallback compatibility

Compiler должен принимать физически валидные конструкции 2/6/20 деталей без benchmark-минимума 100+ nodes. R2 не добавляет hidden nodes и не ослабляет validation ради BAKE. Решение BAKE/FULL остаётся downstream policy; PHYSICS-R2 выдаёт физически типизированную модель для малого объекта.

### R2-F — metamorphic invariants

Обязательные проверки:

- глобальный rigid translation не меняет lengths/stiffness/resistance/response;
- перестановка canonical IDs при сохранении topology/geometry не меняет физические observables;
- изменение length даёт обратную зависимость `k ~ 1/L` и прямую `R ~ L`;
- изменение area даёт `k ~ A` и `R ~ 1/A`;
- изменение material меняет коэффициенты по объявленному law;
- изменение `strength_n` не меняет stiffness или resistance до failure.

### R2-G — independent physical oracle

Acceptance не использует FULL assembler как единственный oracle. Для одного spring и resistive series/parallel fixtures ожидаемые значения вычисляются аналитически из `E*A/L` и `rho*L/A`.

Для линейной статической пружины:

```text
x = F / k
U = 0.5 * k * x^2
W_quasistatic = 0.5 * F * x
```

Проверяется `U == W_quasistatic` с численной tolerance.

## Fixtures

1. One spring: anchor + mass, explicit `A`, explicit damping, capacity 100 N.
2. Load sweep: 70 / 90 / 110 N, guard 80%.
3. Two resistors in series.
4. Two resistors in parallel.
5. Mechanical chains: 2 / 6 / 20 parts.
6. Rigid-translation and ID-permutation variants.
7. Unknown material fail-closed.

## Out of scope

Не входят в PHYSICS-R2:

- COMPOSITION-R3 electromechanical feedback;
- plasticity, fracture propagation, contact/friction, large deformation;
- thermal/hydraulic domains;
- mixture homogenization;
- multidomain energy coupler;
- distributed physics;
- 5k/20k/100k scale claims;
- product/main activation;
- изменение canonical Construction/Matter ownership.

## Acceptance

R2 можно объявить implementation-closed только когда одновременно выполнено:

```text
R2-A material-law contract                    PASS
R2-B axial geometry/material compilation      PASS
R2-C resistive geometry/material compilation  PASS
R2-D guard/capacity separation                PASS
R2-E 2/6/20 small systems                     PASS
R2-F metamorphic invariants                   PASS
R2-G analytic + energy oracles                PASS
R1 focused regression                         PASS
fresh import / fatal scan                     PASS
exact HEAD/TREE evidence                      CAPTURED
```

Implementer validation не считается independent reviewer acceptance. После R2 следующий этап — отдельный `COMPOSITION-R3` Work Order/branch; R3 не входит в эту ветку.
