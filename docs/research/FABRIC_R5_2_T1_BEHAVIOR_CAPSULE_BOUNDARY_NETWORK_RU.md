# FABRIC R5.2A / T1 — Behavior Capsule + Boundary Network Box

## Статус

```text
PROGRAM = FABRIC research
STAGE = R5.2A + R5.2B/T1
PRODUCTION CHECKPOINT = NO
CANONICAL OWNER = Construction / Matter
CAPSULE = DERIVED ONLY
```

## Цель

Первый qualitative-compression fixture должен доказать переход:

```text
human-readable / component-level structure
        ↓ compile
generic physical graph
        ↓ compile
full boundary system
        ↓ exact reduction
PhysicalBakeArtifact
        ↓
BehaviorCapsule
        ↓
cheap executable boundary behavior
```

T1 не добавляет класс Battery/Motor/Laser и не кодирует устройство по имени.

## Fixture

```text
4 electrical boundary ports
128 hidden internal nodes
500+ generic LINEAR_CONDUCTANCE components
        ↓
132-equation full system
        ↓
4-equation exact boundary executable
```

Компоненты имеют generic characterized law:

```text
node_a
node_b
conductance
material_tag
```

На T1 `conductance` уже считается characterized property. Вывод электрических свойств из материалов/геометрии относится к T3 Battery и последующим fixtures.

## Behavior Capsule

Capsule является manifest над существующим PhysicalBakeArtifact, а не новой истиной.

Она фиксирует:

- source frontier / graph provenance;
- boundary contract;
- executable descriptor;
- reduced state schema;
- source component complexity;
- executable complexity;
- compression ratios;
- declared source traversals per execute;
- capability tags;
- build generation.

Runtime T1 намеренно **не получает component graph**. Он получает только:

```text
capsule
PhysicalBakeArtifact
reduction descriptor
live context
boundary efforts
```

Это делает source-component traversal в steady-state невозможным для данного adapter path.

## Positive gates

- raw input order does not change graph/system/reduction/capsule identity;
- full reference vs capsule boundary flow/power within exact envelope;
- 500+ source components → 4 executable equations;
- runtime source traversals = 0;
- 512-call hot loop remains capsule-only;
- source mutation changes graph/reduction/capsule;
- old capsule fails closed against mutated live graph;
- rebuilt capsule executes.

## Negative gates

- isolated internal island → `NO_SAFE_BAKE / RANK_DEFICIENCY`;
- negative conductance is rejected at component-graph contract;
- foreign reduction descriptor cannot execute through capsule.

## Non-claims

T1 does not prove:

- dynamic ROM;
- switching/hybrid compression;
- material-to-cell property derivation;
- hierarchical capsule nesting;
- persistent capsule artifact transport;
- arbitrary nonlinear FABRIC graph compilation.

Those are later R5.2/R5.3 fixtures.


## Prepared execution session

Первый exact measurement показал, что full `BakeExecutionGate` на каждом вызове делает повторную deep-validation всего artifact/source binding и поэтому скрывает вычислительную дешевизну 4×4 relation.

T1 поэтому вводит reduction-specific prepared session:

```text
capsule + artifact + descriptor + live
        ↓ full validation ONCE
prepared exact-linear session
        ↓ each tick
cheap binding fences
+ 4×4 relation
```

Fast path допустим только для текущего exact/stateless/no-guard T1 domain. Любая invalidation, source/frontier/authority/dependency/graph/policy change, non-empty runtime estimator или guard set немедленно запрещают fast execute и требуют reactivation/general gate.

Таким образом provenance не удаляется — он выносится из inner numerical loop.
