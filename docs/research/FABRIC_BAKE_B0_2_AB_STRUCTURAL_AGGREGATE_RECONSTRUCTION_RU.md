# FABRIC-BAKE B0.2-A/B — Structural Aggregate Compiler + Exact Reconstruction Mapping

**Статус:** IMPLEMENTED CANDIDATE / local Ubuntu exact-double chain PASS.  
**Branch:** `research/fabric-bake0-2-structural-aggregate-r1`.  
**Predecessor:** закрытый B0.1 lineage; production acceptance не заявляется.

## 1. Problem statement

B0.2 должен уметь превращать сотни жёстко связанных canonical Construction parts в одно дешёвое rigid physical representation, не уничтожая part/bond identity и не создавая вторую canonical truth.

Подэтапы A/B решают только две фундаментальные задачи:

```text
B0.2-A
rigid structural source
→ deterministic aggregate mass properties / boundary geometry

B0.2-B
aggregate 13-DOF state
↔ exact per-part rigid reconstruction mapping
```

RefinementGuard, local unbake execution и topology split относятся к B0.2-C/D/E и намеренно не имитируются в A/B.

## 2. Pre-build design decision

Рассматривались два варианта.

### Вариант 1 — сразу собрать PhysicalBakeArtifact

Отклонён.

Для structural bake скрытые internal damage/failure процессы требуют RefinementGuard. Выпустить executable `PhysicalBakeArtifact` до B0.2-C означало бы обойти B0.0 fail-closed contract.

### Вариант 2 — intermediate structural candidate

Принят.

```text
StructuralAggregateCompiler
        ↓
StructuralAggregateDescriptor
        +
StructuralReconstructionMapping
        ↓
STRUCTURAL_AGGREGATE_READY_FOR_GUARDS
```

При этом:

```text
physical_bake_artifact_emitted = false
next_required_stage = B0.2-C_REFINEMENT_GUARDS
```

Так A/B можно проверить математически и детерминированно, не делая небезопасный artifact исполняемым.

## 3. Input contract

Compiler принимает:

```text
construct_id
source_frontier_hash
parts[]
bonds[]
boundary_anchors[]
reconstruction_version
minimum_part_count
```

Каждая part содержит:

```text
part_id
region_id
mass
position in canonical construction frame
orientation in canonical construction frame
full local 3x3 inertia tensor
finite local support point set
```

Каждая bond должна быть явно `rigid=true`.

Compiler fail-closed проверяет:

- минимум 100 parts для текущего B0.2-A/B scope;
- положительную mass;
- unit quaternion;
- symmetric positive-definite local inertia tensor;
- существующие bond endpoints;
- жёсткость всех bonds;
- connected rigid graph;
- valid boundary anchors;
- непустой support set каждой part.

## 4. Aggregate mass properties

Total mass:

```text
M = Σ m_i
```

Center of mass:

```text
c = (1/M) Σ m_i r_i
```

Aggregate body frame в A/B фиксируется как:

```text
origin      = CENTER_OF_MASS
orientation = CONSTRUCTION_FRAME
```

Полный inertia tensor вычисляется без диагонального упрощения:

```text
I = Σ [ R_i I_i R_i^T
        + m_i ((d_i·d_i)E - d_i d_i^T) ]

d_i = r_i - c
```

То есть используется full 3×3 rotated inertia + parallel-axis theorem.

## 5. Boundary anchors and rigid Jacobian

Для каждого boundary anchor компилируются:

```text
position_from_com
orientation_from_aggregate
linear_velocity_jacobian_body
```

Rigid point velocity:

```text
v_anchor = v_com + ω × r
```

Jacobian хранится как 3×6 mapping для rigid twist.

B0.2-A/B не решает contact. Он только сохраняет exact anchor kinematics и finite support envelope как substrate для последующих B0.2/B0.3 стадий.

## 6. Collision / support envelope

Все supplied per-part support points переводятся в aggregate COM frame и канонически сортируются.

```text
support(d) = argmax_i d · p_i
```

Это exact finite support set для переданных structural support vertices. A/B не заявляет general concave contact bake, GJK/EPA replacement или B0.3 contact semantics.

## 7. Exact reconstruction mapping

Для каждой canonical part хранится derived mapping:

```text
part_id
region_id
position_from_com
orientation_from_aggregate
```

Canonical part/bond topology не копируется как новая truth. Mapping только связывает reduced rigid state с canonical identities.

Reduced state:

```text
position(COM)        3
orientation          4
linear_velocity      3
angular_velocity     3
----------------------
                     13
```

Reconstruction:

```text
r_world = Q r_local
p_i     = p_com + r_world
Q_i     = Q Q_i_local
v_i     = v_com + ω × r_world
ω_i     = ω
```

Projection FULL → REDUCED использует deterministic reference part, восстанавливает aggregate pose/twist и затем проверяет все остальные parts против rigid mapping. Любое несоответствие:

```text
NON_RIGID_FULL_STATE
→ fail closed
```

## 8. Region mapping

500-part acceptance fixture разделён на 25 deterministic regions по 20 parts.

A/B region mapping уже позволяет однозначно ответить:

```text
region_id → sorted canonical part_ids
```

Это foundation для B0.2-C RefinementGuard и B0.2-D bounded local unbake, но A/B пока не решает, когда region надо unbake.

## 9. Conservation audit

Для reconstructed rigid state проверяется equivalence:

```text
Σ m_i v_i
≈
M v_com
```

и angular momentum относительно COM:

```text
Σ [(r_i-c) × m_i v_i + I_i_world ω]
≈
I_aggregate_world ω
```

Acceptance fixture даёт errors порядка `1e-12`.

## 10. Determinism

Compiler сначала canonical-sort:

```text
parts by part_id
bonds by bond_id
anchors by anchor_id
regions by region_id
support points by point_id
```

Reverse input order обязан производить identical descriptor/mapping checksums.

Canonical source mutation меняет source frontier и/или mass properties, поэтому новый compile получает новый content identity.

## 11. Acceptance fixture

```text
parts                 = 500
rigid bonds           = 499
regions               = 25
boundary anchors      = 4
support points        = 4000
full rigid-state DOF  = 6500
reduced rigid DOF     = 13
state reduction ratio = 500x
```

Positive path:

- aggregate compile;
- descriptor validation;
- exact mass/COM;
- full inertia symmetry/SPD;
- deterministic reversed-input compile;
- REDUCED → FULL reconstruction;
- FULL → REDUCED projection;
- rigid roundtrip;
- linear/angular momentum equivalence;
- boundary anchor pose/velocity/Jacobian;
- support mapping;
- deterministic source mutation rebuild.

Negative path:

```text
non-rigid bond
→ NON_RIGID_STRUCTURAL_BOND

disconnected graph
→ DISCONNECTED_STRUCTURAL_AGGREGATE

<100 parts
→ INSUFFICIENT_STRUCTURAL_COMPLEXITY_REDUCTION

invalid inertia
→ NONPOSITIVE_STRUCTURAL_INERTIA

perturbed non-rigid full state
→ NON_RIGID_FULL_STATE
```

## 12. Development evidence

Engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
Linux binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Canonical local runner:

```bash
GODOT_BIN=<double-godot> ./RUN_FABRIC_BAKE_B0_2_AB_TESTS.sh
```

Observed full chain:

```text
B0.0 Acceptance       PASS 33 assertions
B0.1 Acceptance       PASS 64 assertions
B0.1 Playground       PASS
B0.2-A/B Acceptance   PASS 76 assertions
B0.2-A/B Playground   PASS
```

Primary B0.2-A/B output:

```text
parts=500
state=6500->13
ratio=500.0x
regions=25
supports=4000
linear_momentum_error=2.32e-12
angular_momentum_error=3.32e-12
```

Exact implementation-head verification is recorded separately after Git commit; this development pass is not itself a checkpoint closure.

## 13. Non-claims

B0.2-A/B does not claim:

- B0.2 checkpoint closure;
- executable structural PhysicalBakeArtifact;
- certified RefinementGuard;
- local unbake execution;
- damage/bond failure prediction;
- topology split/rebake;
- general convex contact bake;
- production readiness.

## 14. Next

```text
B0.2-C
REFINEMENT GUARD FIELD

boundary / local loads
→ conservative regional capacity bound
→ mapped canonical region
→ early safe refinement request
```

Only after guard certification may the structural candidate be promoted into an executable approximate PhysicalBakeArtifact.
