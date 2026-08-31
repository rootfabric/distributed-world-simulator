# FABRIC-BAKE B0.2-C — Refinement Guard Field

**Статус:** RESEARCH SLICE CLOSED / EXACT-HEAD DOUBLE PASS.  
**Branch:** `research/fabric-bake0-2-refinement-guards-r1`.  
**Executable implementation HEAD:** `ffd53302d891b4d64b88589c434c56e76aef1eaa`.  
**Executable TREE:** `754bdd8a38246afe7bbd85eba74615ef7f0bb3e7`.  
**Parent / B0.2-A/B frontier:** `a1b8631a86b9bb896a6ca9a4871a5f0d2cee5b2a`.  
Production acceptance не заявляется.

## 1. Goal

B0.2-A/B уже доказал deterministic structural aggregate и exact rigid reconstruction mapping, но намеренно не выпускал executable `PhysicalBakeArtifact`: скрытые bond failure/damage процессы нельзя безопасно скрывать без conservative refinement guard.

B0.2-C добавляет derived guard field:

```text
canonical 500-part rigid tree
        +
certified per-bond force/moment capacities
        +
exact reconstruction mapping
        ↓
StructuralRefinementGuardField
        ↓
runtime complete external wrench inventory
+ aggregate a / omega / alpha
        ↓
rigid-tree inverse dynamics
        ↓
hidden bond wrench demand
        ↓
canonical region utilization
        ↓
SAFE | REFINEMENT_REQUIRED
```

Guard не становится canonical truth и не мутирует Construction.

## 2. Certified structural scope

Текущий C-slice сертифицирует только connected rigid **tree**:

```text
parts = N
bonds = N - 1
connected
all bonds rigid
```

Cyclic/redundant/statistically indeterminate graph не получает эвристическое распределение нагрузок:

```text
NO_SAFE_GUARD_CYCLIC_OR_REDUNDANT_STRUCTURAL_GRAPH
```

Это сознательная fail-closed граница B0.2-C R1.

## 3. Compile-time guard field

Compiler связывает guard field с:

- exact `source_frontier_hash`;
- B0.2 structural aggregate descriptor checksum;
- exact reconstruction mapping checksum;
- capacity certificate hash;
- canonical root part;
- sorted part/bond identities;
- canonical region mapping;
- explicit trigger ratio;
- uncertainty margin;
- residual force/moment tolerances;
- evaluator version.

Каждый hidden bond хранит derived model:

```text
bond_id
parent_part_id
child_part_id
mapped_region_id
point_from_com
certified_force_capacity
certified_moment_capacity
uncertainty_ratio
```

Каждый canonical region получает B0.0 `RefinementGuard`, связанный с region identity.

## 4. Runtime evaluator

Runtime принимает только complete external wrench inventory и rigid aggregate kinematics:

```text
linear_acceleration_body
angular_velocity_body
angular_acceleration_body
external_wrenches[]
complete_external_wrench_set = true
```

Для каждой part вычисляется требуемый rigid-body wrench, затем post-order tree accumulation восстанавливает internal bond wrench.

Для bond:

```text
force_utilization  = |F_bond| / certified_force_capacity
moment_utilization = |M_bond| / certified_moment_capacity
utilization        = force_utilization + moment_utilization
```

Region peak затем подаётся в `RefinementGuard`.

Если inventory неполон, descriptor/source binding неверен, dynamics residual превышает tolerance или capacity evidence не покрывает graph, runtime fail closed.

## 5. Main falsifier — early refinement before capacity crossing

Acceptance fixture:

```text
parts   = 500
bonds   = 499
regions = 25
```

Weak hidden bond:

```text
bond/b0-2-0257
region/b0-2-012
```

Observed deterministic sweep:

```text
load = 20
utilization = 0.500000
STRUCTURAL_GUARD_SAFE

load = 30
utilization = 0.750000
STRUCTURAL_REFINEMENT_REQUIRED

load = 40
certified capacity boundary

load = 41
utilization = 1.025000
STRUCTURAL_REFINEMENT_REQUIRED
```

То есть first guard trigger происходит на `30`, а certified capacity пересекается только на `40`.

Это главный B0.2-C safety claim: hidden detail запрашивается **до** выхода за certified envelope.

## 6. Fail-closed cases covered

Acceptance explicitly covers:

- cyclic/redundant graph -> `NO_SAFE_GUARD`;
- incomplete external wrench inventory;
- inconsistent aggregate rigid dynamics;
- foreign structural descriptor binding;
- foreign reconstruction mapping binding;
- unknown part in external wrench;
- duplicate wrench identity;
- missing/extra capacity coverage;
- capacity certificate hash mismatch;
- invalid capacity / uncertainty;
- insufficient safety margin;
- non-rigid source bond;
- deterministic reverse input ordering.

## 7. Exact verification

Pinned engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
binary sha256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact source export workflow:

```text
run: 33357380503
artifact: 9745553457
name: fabric-bake-b0-2-c-exact-source-ffd53302
artifact digest:
sha256:bba17f89324308083b3a2cdacfe29665709afdb9f849d77faa98bf6cbf8f32cc
```

Workflow asserted:

```text
HEAD = ffd53302d891b4d64b88589c434c56e76aef1eaa
TREE = 754bdd8a38246afe7bbd85eba74615ef7f0bb3e7
```

Tracked source archive:

```text
sha256 f8d690545e49d22fa02daca2f5e86465aedcf2b2f40a351d4d0b221fb2a5a79f
```

Two independent fresh-filesystem Ubuntu/Linux runs both produced:

```text
B0.0 Acceptance       PASS 33/33
B0.1 Acceptance       PASS 64/64
B0.1 Playground       PASS
B0.2-A/B Acceptance   PASS 76/76
B0.2-A/B Playground   PASS
B0.2-C Acceptance     PASS 118/118
B0.2-C Playground     PASS
```

Deterministic B0.2-C field identity:

```text
d3bbb115fb79d3159f1446eb2d589754c50b99892fd8b96c682de65e85d1243a
```

Post-run audit over `5043` tracked files for each fresh run:

```text
missing = 0
changed = 0
```

Windows remains `PASS_BY_POLICY / NON-GATING` under the FABRIC-BAKE platform policy.

## 8. Non-claims

B0.2-C does **not** claim:

- local unbake execution;
- mixed FULL/BAKED runtime topology;
- canonical bond mutation or break;
- topology split/rebake;
- damage constitutive model;
- safe guard inference for cyclic/redundant structures;
- executable final B0.2 `PhysicalBakeArtifact`;
- B0.2 overall closure;
- production readiness.

## 9. Next

```text
B0.2-D
BOUNDED LOCAL UNBAKE
```

C now provides the deterministic canonical region request that D must consume without unbaking the whole 500-part construct.
