# FABRIC R5.2A / T1 — Behavior Capsule + Boundary Network Box

## Статус

**Статус:** EXACT T1 PASS / fresh review + verifier pending.

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


## Exact T1 result — run 35514232032

```text
SUBJECT_HEAD = 555368186cb46971e2ad6828ac021f8b4f1f3ae1
SUBJECT_TREE = 8d865d9253099e729a9be7e050023cc32b043682

samples = 3/3 PASS
aggregate job = 106087426611
artifact = 10606785462
digest = sha256:be698db4fc804a8d3a519fb0a192c2f07fe9906bd3165a0944e43ad8e04b57e0

deterministic hash =
9afd2af8820932b6103c8a7bc8b64b0a6f751dc08498a3881d6aa5d35eec7237
```

### Доказанная qualitative compression

```text
543 generic conductance components
        ↓
128 hidden nodes + 4 boundary nodes
        ↓
132 full equations
        ↓ exact reduction
4 executable boundary equations

equation compression       = 33.0×
component/executable ratio = 135.75×
source traversals / execute = 0
```

Exact full↔capsule errors:

```text
max boundary flow error  = 8.53e-14
max boundary power error = 2.84e-12
```

### Prepared execution

Первый корректный T1 показал, что deep PhysicalBake provenance validation на каждом вызове стоила больше самой 4×4 модели. После переноса полной validation на activation boundary:

```text
one-time prepare/full validation ≈ 9.09 ms

old full-gate path:
  128 calls / 1,212,415 µs
  ≈ 9.47 ms/call

prepared path:
  4096 calls / 80,306 µs
  ≈ 19.6 µs/call

observed inner-loop speedup ≈ 483×
```

Это observation на одном типе GitHub-hosted runner, а не universal performance threshold.

Prepared path сохраняет fail-closed fences для STALE/invalidation/source frontier/authority/dependencies/graph/compiler/boundary/policy/runtime-domain и запрещает T1 fast path при runtime estimator или refinement guards.

### Trust boundary fast path

Per-tick fast path использует hashes/checksums, выпущенные canonical owner live-context как immutable snapshot tokens. Произвольное изменение вложенного Dictionary без обновления его canonical hash/checksum считается нарушением live-context contract и T1 его не объявляет поддерживаемым.

Это не второй revision/authority system. Future persistent/hierarchical capsule work может получить owner-issued compact revision token.
