# v17.9.0 — RL0 Unified Representation Contracts

```text
checkpoint: v17.9.0-simulation-rl0-representation-contracts
build_id: rl0-unified-representation-contracts
base: v17.8.0-simulation-mw8-regional-authority-handoff
branch: feature/rl0-representation-contracts
status: CANDIDATE FOR INDEPENDENT REVIEW
```

## Цель

Зафиксировать общий lifecycle обобщённых представлений для Dynamic Matter Fabric и Construction C18 до реализации конкретных mesh builders.

RL0 не создаёт meshes, images, collision shapes или Godot nodes. Он определяет, как source revision связывается с detail/simplified/proxy/impostor artifact, как observer задаёт error budgets и как cache/invalidation остаются производными от канонического состояния.

## Реализовано

### Source provenance

`RepresentationSourceRevision` содержит:

- `source_domain`: `MATTER` или `CONSTRUCTION`;
- canonical `source_id`;
- `authority_epoch`;
- `source_revision`;
- `source_hash`;
- `dependency_hash`;
- checksum.

Interest и artifacts привязаны к полному source checksum. Artifact старой revision не может быть выбран для нового request.

### Representation identity

`RepresentationKey` содержит:

- source revision;
- spatial/semantic `scope_id`;
- `lod_level`;
- artifact kind;
- variant ID.

Convention:

```text
LOD 0 = finest
larger LOD level = coarser
```

Kinds:

```text
DETAIL
SIMPLIFIED_MESH
MACRO_PROXY
IMPOSTOR
NONE
```

### Artifact manifest

`RepresentationArtifactManifest` хранит только metadata:

- content SHA-256;
- byte size;
- encoding/media type;
- geometric error;
- bounds;
- collision/interior capabilities;
- build generation.

`NONE` не может иметь artifact manifest.

### Interest and selection

`RepresentationInterestRequest` задаёт:

- exact required source revision;
- distance и projection scale;
- maximum screen/geometric error;
- collision/interior requirements;
- bandwidth budget;
- preferred kinds;
- request revision.

`RepresentationSelector` выбирает самый грубый candidate, который удовлетворяет всем fences.

### Dependency and invalidation

`RepresentationDependencySet` сортирует child revisions и вычисляет deterministic dependency hash. Это база RL1 ancestor dirty propagation.

`RepresentationInvalidation` проверяет:

- source identity continuity;
- monotonic authority epoch/revision;
- dirty bounds;
- affected scopes;
- reason и tick.

### Cache lifecycle

`RepresentationCacheEntry` поддерживает:

```text
BUILDING
READY
STALE
EVICTED
FAILED
```

READY resident bytes обязаны совпадать с manifest. EVICTED хранит manifest, но не resident bytes. BUILDING/FAILED не могут притворяться готовым artifact.

## Обновлённая дорожная карта

Введена сквозная серия RL:

```text
MW8 accepted
→ RL0 contracts
→ RL1 Matter summary pyramid
→ MW9 durable handoff
→ MW10 cross-region transactions
→ RL2 Matter multiresolution meshing
→ RL3 network artifact streaming
→ RL4 Construction HLOD backend
→ RL5 cache/build scheduler
→ RL6 scale acceptance
→ MW11–MW14
→ MI/MP integration
```

Подробности находятся в:

- `docs/architecture/REPRESENTATION_LOD_FABRIC_RU.md`;
- `docs/plans/REPRESENTATION_LOD_ROADMAP_RU.md`;
- обновлённом `docs/plans/MUTABLE_WORLDS_ROADMAP_RU.md`.

## Focused runner

```text
RUN_RL0_REPRESENTATION_CONTRACTS_TESTS.ps1
RUN_RL0_REPRESENTATION_CONTRACTS_TESTS.sh
```

Проверяются:

- config identity и boundaries;
- Matter и Construction source revisions;
- exact-field/checksum rejection;
- LOD/key bounds;
- content-addressed artifact manifest;
- deterministic dependency ordering/hash;
- coarsest-acceptable selection;
- screen/geometric error budgets;
- collision/interior capability fences;
- bandwidth and preferred-kind fences;
- stale source rejection;
- mutation/handoff invalidation;
- authority rollback rejection;
- cache state invariants/transitions;
- runtime Godot object rejection.

Статическая topology focused-сценария — `92 assertions`; точное runtime-значение и время фиксируются первым независимым successful run.

## Граница

RL0 не меняет:

- MW8 authority handoff;
- MW7 regional replication;
- MW3 mesher;
- C18 code branch;
- production Moon;
- world catalog;
- Item Graph;
- persistence bytes;
- network wire protocol.

Следующий этап: RL1 — Matter Summary Pyramid and Dirty Propagation.
