# FABRIC-BAKE B0.0 — Bake Foundation Contracts

**Статус:** RESEARCH CHECKPOINT CLOSED / EXACT-HEAD DOUBLE PASS.  
**Ветка:** `research/fabric-bake0-reducible-world-fabric-r1`.  
**Base / dual-track fork:** `962b9c1bbf7f04c7853f1fb0e36480cf54f3250d`.  
**Physical predecessor:** FABRIC0.15 — RESEARCH CANDIDATE CLOSED / EXACT DOUBLE PASS / DRAFT REVIEW CANDIDATE.  
**Production acceptance:** не заявляется.

## 1. Цель checkpoint

B0.0 создаёт фундаментальный executable contract layer для будущих B0.1+ reduction stages без введения второго canonical truth, второго revision system или device-specific baked runtime.

Truth hierarchy:

```text
canonical Construction / Matter
        ↓
derived FABRIC graph
        ↓
derived PhysicalBakeArtifact
```

`FABRIC` не является canonical source domain.

## 2. Реализованные контракты

```text
CanonicalSourceFrontier
AuthorityEnvelope
PhysicalBoundaryContract
BakeDependencySet
BakeSourceBinding
ValidatedDomain
ErrorEnvelope
RuntimeErrorEstimator
ConservationEnvelope
RefinementGuard
ReconstructionDescriptor
BakeStateMapping
PhysicalBakeArtifact
BakeInvalidation
BakeCompileResult
```

Дополнительно реализованы:

```text
FabricBakeFoundationCompiler
BakeExecutionGate
FabricBakeBridge0
```

## 3. CanonicalSourceFrontier

Frontier использует существующий `RepresentationSourceRevision` и поэтому наследует canonical source domains:

```text
CONSTRUCTION
MATTER
```

Список source revisions:

- сортируется детерминированно по `source_domain|source_id`;
- обязан быть unique;
- валидирует каждый source revision существующим Representation contract;
- получает deterministic `frontier_hash`;
- может содержать несколько canonical sources.

Попытка использовать `FABRIC` как source domain отвергается существующим source-revision validator.

## 4. AuthorityEnvelope

Envelope связывает:

```text
execution_owner
source_authority_frontier[]
mutable_source_ids[]
readonly_source_ids[]
authority_epoch_binding
distributed_execution_protocol
```

B0.x safety rule:

```text
mutable source owner != execution_owner
→ NO_SAFE_BAKE / AUTHORITY_ENVELOPE_CROSSED
```

Непустой distributed execution protocol в B0.0 также fail-closed:

```text
UNSUPPORTED_DISTRIBUTED_BAKE_PROTOCOL
```

То есть B0.0 не маскирует cross-authority execution под локальный bake.

## 5. PhysicalBoundaryContract

Boundary остаётся acausal contract surface.

Каждый port фиксирует:

```text
physical_domain
effort_quantity
flow_quantity
effort_dimension[7]
flow_dimension[7]
frame
orientation
conservation_group
event_observables
```

Physical dimensions валидируются структурно; port ordering и `contract_hash` детерминированы.

## 6. Source binding

`BakeSourceBinding` связывает artifact сразу с:

```text
canonical_source_frontier
frontier_hash
authority_envelope
dependency_set
dependency_hash
fabric_graph_hash
fabric_compiler_version
boundary_contract_hash
bake_policy_hash
checksum
```

Authority frontier обязан иметь тот же exact set canonical sources и authority epochs, что и canonical frontier.

## 7. Validity / error / conservation

`ValidatedDomain` фиксирует:

```text
exact_frontier_hash
exact_fabric_graph_hash
scalar_ranges[]
allowed_modes[]
time_horizon_s
```

Runtime выход за domain не допускает silent extrapolation и возвращает `BAKE_VALIDITY_EXIT_*`.

`ErrorEnvelope` хранит deterministic bounds для effort/flow/power/motion, energy/momentum drift, event time и horizon.

`RuntimeErrorEstimator` проверяется против ErrorEnvelope и не может расширять его.

`ConservationEnvelope` отдельно фиксирует допустимые power/energy/momentum/matter deviations.

## 8. RefinementGuard

Guard содержит:

```text
guard_id
observed_boundary_quantities[]
conservative_bound
trigger_threshold
mapped_source_region
required_refinement_level
uncertainty_margin
```

Исполнение fail-closed:

```text
guard value unavailable
→ BAKE_REFINEMENT_GUARD_UNOBSERVED

observed + uncertainty >= trigger
→ BAKE_REFINEMENT_REQUIRED
```

То есть hidden risk не разрешается трактовать как «данных нет — продолжаем reduced execution».

## 9. ReconstructionDescriptor + StateMapping

Artifact без reconstruction descriptor недействителен.

Descriptor:

- связан exact `source_frontier_hash`;
- содержит deterministic mapping/version/event frontier;
- задаёт hidden-state policy;
- содержит canonical region mappings;
- обязан покрывать **каждый source** из CanonicalSourceFrontier;
- не может ссылаться на source вне frontier.

`BakeStateMapping` отдельно связывает full/reduced state schemas, projection и reconstruction descriptor checksum.

B0.0 пока не реализует numerical unbake: он фиксирует контракт, который B0.2+ обязан исполнять.

## 10. PhysicalBakeArtifact

Physical artifact имеет отдельную schema и намеренно не переиспользует `RepresentationArtifactManifest`.

Он объединяет source binding, boundary, reduced-model/state descriptors, validity/error/conservation, guards, reconstruction/state mapping и build generation.

Для `APPROXIMATE` artifact минимум один RefinementGuard обязателен.

Artifact остаётся derived/cacheable data и не владеет canonical world truth.

## 11. NO_SAFE_BAKE

`BakeCompileResult` различает:

```text
BAKE_READY
NO_SAFE_BAKE
```

B0.0 compiler уже выдаёт `NO_SAFE_BAKE` для:

```text
AUTHORITY_ENVELOPE_CROSSED
UNSUPPORTED_DISTRIBUTED_BAKE_PROTOCOL
UNCERTIFIABLE_ERROR_ENVELOPE
UNCERTIFIABLE_REFINEMENT_GUARD
INSUFFICIENT_COMPLEXITY_REDUCTION
```

Schema заранее фиксирует также следующие reason codes для последующих stages:

```text
RANK_DEFICIENCY
UNSAFE_ELIMINATION
RECONSTRUCTION_UNAVAILABLE
UNSUPPORTED_HYBRID_MODE
NEAR_CRITICAL_DYNAMICS
```

Malformed contract input не маскируется под физически осмысленный `NO_SAFE_BAKE`: он отклоняется validator-ом.

## 12. Physical execution gate

`BakeExecutionGate` является обязательной границей между валидным artifact byte object и правом реально использовать его как physics.

Gate проверяет:

```text
artifact state == READY
no matching BakeInvalidation
exact canonical frontier
exact authority envelope
exact dependency hash
exact FABRIC graph hash
exact FABRIC compiler version
exact boundary contract hash
exact bake policy hash
ValidatedDomain
RuntimeErrorEstimator
RefinementGuards
```

Ключевое правило:

```text
STALE
→ STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN
```

То есть stale state не является advisory metadata.

## 13. BAKE-BRIDGE-0

Bridge не создаёт собственный canonical revision protocol.

Pipeline:

```text
RepresentationSourceRevision
        ↓
existing RepresentationInvalidation
        ↓
FabricBakeBridge0
        ↓
BakeInvalidation(SOURCE_REVISION)
        ↓
STALE
        ↓
execution forbidden immediately
```

Bridge принимает существующий `RepresentationInvalidation`, сверяет exact previous revision с bound frontier, exact new revision с current frontier и только после этого создаёт physical invalidation.

Authority rollback отсекается существующим Representation invalidation validator до BAKE layer.

## 14. Focused acceptance

Проверено на:

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb
```

Результат:

```text
FABRIC-BAKE B0.0 Acceptance: PASS (33 assertions)

artifact:
cde434f9d055dfc597450c4ad1aff4076fd87349c948cb7fd39e39d8cc1c190a

frontier:
138d1685648791985a25569760c28960d4e71c356ca01d75ab394aef8e0b0fc8

bridge invalidation:
8b3e16cc7d24afe2a3e68862206e32bad43eb50eba3d792f2486b9303e611b6c
```

Проверены:

```text
multi-source deterministic frontier
FABRIC canonical source rejection
BAKE_READY happy path
cross-authority mutable → NO_SAFE_BAKE
uncertifiable guard → NO_SAFE_BAKE
missing reconstruction → invalid artifact
wrong canonical revision → execution reject
dependency mismatch → execution reject
wrong FABRIC graph → execution reject
wrong FABRIC compiler → execution reject
wrong boundary contract → execution reject
STALE → execution forbidden
ValidatedDomain exit → execution forbidden
RefinementGuard trigger → refinement required
RuntimeErrorEstimator envelope violation → execution reject
authority rollback → existing invalidation reject
canonical mutation → BAKE-BRIDGE-0 invalidation
old artifact after mutation → execution forbidden
```

## 15. Что B0.0 не утверждает

B0.0 не доказывает:

```text
Schur reduction
structural aggregate equivalence
local numerical unbake
contact/wrench reduction
dynamic ROM
hybrid lazy-mode compilation
adaptive scheduler integration
production readiness
```

Это foundation checkpoint. Первый reduction experiment остаётся B0.1.

## 16. Следующий gate

Independent exact-head verification выполнен; B0.0 закрыт как research checkpoint.

Следующий BAKE stage:

```text
B0.1
EXACT BOUNDARY REDUCTION
well-posed eliminable linear block
→ exact Schur/elimination
→ boundary equivalence + rank/passivity/determinism/cost evidence
```

Physical Core продолжает независимо:

```text
FABRIC0.16
GENERAL CONVEX MULTIPOINT MCP
```
