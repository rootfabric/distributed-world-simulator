# FABRIC-BAKE B0.1 — Exact Boundary Reduction / Schur elimination

**Статус:** IMPLEMENTED CANDIDATE / EXACT-HEAD VERIFICATION PENDING.  
**Ветка:** `research/fabric-bake0-1-exact-boundary-reduction-r1`.  
**Predecessor:** B0.0 closure `d389b8ed72ffbed8949279b42089da3687125a90`.  
**Production acceptance:** не заявляется.

## Цель

B0.1 — первый computational bake после B0.0. Accepted scope намеренно узкий:

```text
2–8 external physical ports
+
100+ internal linear algebraic unknowns
+
well-posed eliminable internal block
        ↓
exact Schur elimination
        ↓
small boundary relation
```

B0.1 не заявляет универсальный reducer произвольного FABRIC graph.

## Математический контракт

Полная acausal relation:

```text
[ A_bb  A_bi ] [ e_b ]   [ r_b ]
[ A_ib  A_ii ] [ x_i ] = [ r_i ]
```

Boundary flow:

```text
f_b = A_bb e_b + A_bi x_i - r_b
```

Для невырожденного `A_ii`:

```text
S     = A_bb - A_bi A_ii^-1 A_ib
r_red = r_b  - A_bi A_ii^-1 r_i

f_b = S e_b - r_red
```

Явная inverse не строится. Используется deterministic partial-pivot LU и повторные triangular solves.

## Executable pieces

```text
LinearBoundarySystem
DenseLinearAlgebra
ExactBoundaryReductionDescriptor
ExactBoundaryReducer
ExactBoundaryBakeCompiler
ExactBoundaryRuntime
```

`LinearBoundarySystem` канонизирует boundary/internal ids вместе с rows/columns/RHS и получает deterministic `system_hash`.

`DenseLinearAlgebra` содержит bounded B0.1 substrate: LU, solve, rank evidence, matrix/vector operations, symmetry/nullspace audits и passive-Laplacian structural certificate.

## Fail-closed boundary

Pivot threshold:

```text
threshold = pivot_relative_tolerance * max_abs(A_ii)
```

Если deterministic pivot не проходит threshold:

```text
RANK_DEFICIENCY
→ NO_SAFE_BAKE
```

Не используются pseudo-inverse, hidden regularization, arbitrary gauge fixing или least-squares fallback.

Для requested passive/reciprocal scope также fail-closed проверяются:

- source/reduced symmetry;
- row-sum nullspace;
- non-negative diagonal;
- non-positive off-diagonal;
- zero independent source RHS;
- effort+flow dimension = power dimension.

Нарушение safe reduction:

```text
UNSAFE_ELIMINATION
→ NO_SAFE_BAKE
```

## Exact artifact integration

B0.1 не создаёт второй artifact universe:

```text
LinearBoundarySystem
        ↓
ExactBoundaryReducer
        ↓
ExactBoundaryReductionDescriptor
        ↓
B0.0 FabricBakeFoundationCompiler
        ↓
PhysicalBakeArtifact(reduction_class = EXACT)
```

`PhysicalBakeArtifact.reduced_model_descriptor_hash` равен checksum exact reduction descriptor.

Runtime требует:

```text
artifact.reduced_model_descriptor_hash
==
reduction_descriptor.checksum
```

до существующего B0.0 `BakeExecutionGate`. Поэтому valid artifact не может исполняться с foreign reduced matrix.

Reducer implementation и numerical policy входят в provenance через отдельную reducer dependency и effective bake-policy hash.

## Acceptance fixture

Primary fixture:

```text
boundary ports:       4
internal variables: 128
full equations:      132
reduced equations:     4
expected internal rank: 128
expected reduced rank:   3
```

Reduced rank 3 нормален для passive Laplacian: общая potential-gauge mode остаётся boundary nullspace; устраняемый internal block при этом full-rank.

Проверяются несколько boundary excitations:

```text
FULL effort == BAKED effort
FULL flow   ≈  BAKED flow
FULL power  ≈  BAKED power
```

в machine-precision-scale envelope.

Обязательные adversarial cases:

```text
singular internal block
→ RANK_DEFICIENCY / NO_SAFE_BAKE

non-passive requested scope
→ UNSAFE_ELIMINATION / NO_SAFE_BAKE

internal block < 100
→ INSUFFICIENT_COMPLEXITY_REDUCTION / NO_SAFE_BAKE

non-power-conjugate boundary dimensions
→ compile rejection

foreign reduction descriptor
→ runtime rejection

canonical source mutation
→ BAKE-BRIDGE-0 invalidation
→ old artifact non-executable
→ deterministic rebuild
```

## Runtime-cost evidence

Для 128→4 fixture deterministic operation-count proxy:

```text
runtime_work_ratio = 1089x
```

Это не wall-clock production benchmark; это falsifiable arithmetic-work evidence, достаточное для B0.1 complexity-reduction claim.

## Canonical runners

Linux:

```bash
./RUN_FABRIC_BAKE_B0_1_TESTS.sh
```

Windows (optional manual portability check, non-gating):

```powershell
.\RUN_FABRIC_BAKE_B0_1_TESTS.ps1
```

FABRIC-BAKE closure does not require a Windows run. Windows is `PASS_BY_POLICY` unless a
checkpoint explicitly introduces a platform-specific exception.

Runner выполняет:

```text
B0.0 predecessor acceptance
→ B0.1 focused acceptance
→ B0.1 playground
```

и требует Godot `4.7.1.stable.double.custom_build.a13da4feb`.

## Closure rule

IMPLEMENTED не означает CLOSED.

B0.1 может получить:

```text
RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE PASS
```

только после fresh full-repository exact-HEAD execution B0.0→B0.1 на canonical Ubuntu/Linux double-Godot path, exact HEAD/TREE evidence и отдельной closure фиксации. Отдельный Windows run не требуется.

Следующий roadmap checkpoint после закрытия B0.1:

```text
B0.2
STRUCTURAL AGGREGATE BAKE
+ REFINEMENT GUARDS
+ LOCAL UNBAKE
```
