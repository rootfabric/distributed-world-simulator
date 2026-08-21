# Network Framework-Ready Development Policy

**Статус:** обязательная дополнительная архитектурная policy для активной разработки network / seamless / distributed-authority направлений.

## 1. Цель

Текущая разработка сетевой части `distributed-world-simulator` продолжается по существующим roadmap, Work Order, Project Control, review и acceptance-процессам.

Эта policy не создаёт отдельный framework-проект, не открывает новый roadmap и не разрешает массовый refactor.

Цель: развивать текущий network/distributed runtime так, чтобы зрелую версию позднее можно было выделить в самостоятельный reusable framework без переписывания фундаментальных authority, handoff, replication, projection, recovery и transport semantics.

На текущем этапе `Distributed World Simulator` является одновременно продуктом, главным integration environment и incubation environment будущего reusable network runtime.

## 2. Приоритет текущей задачи

Текущий одобренный Work Order и canonical Project Control всегда имеют приоритет над будущей framework extraction.

Implementer обязан:

1. выполнить текущий Work Order;
2. сохранить существующие invariants и ownership boundaries;
3. не расширять scope ради framework;
4. при выборе между двумя одинаково корректными решениями предпочитать решение с меньшей зависимостью от simulator-specific domain.

Нельзя задерживать текущий V0/NX/SM прогресс ради архитектурной чистоты будущей библиотеки.

## 3. Запрет преждевременного выделения

Без отдельного формального Work Order запрещается:

- создавать отдельный GitHub repository/package для framework;
- массово переносить или переименовывать NX/SM/network code;
- переписывать принятые semantics только ради generic API;
- вводить package/version synchronization между simulator и network runtime;
- создавать второй gameplay truth, второй Item Graph или вторую authority model;
- превращать framework-readiness в самостоятельный scope текущей задачи.

## 4. Целевая dependency direction

Долгосрочная зависимость должна стремиться к:

```text
Simulator Domain
      |
      v
Simulator Network Adapters
      |
      v
Reusable Network Runtime
```

Разрешённое направление:

```text
simulator -> network
```

Нежелательное направление, которое не следует добавлять без необходимости:

```text
network -> simulator gameplay domain
```

Generic network runtime не должен без необходимости зависеть от Item Graph contents, inventory semantics, Construction, Matter, Ecology, конкретных ресурсов, конкретных кораблей, Earth/Moon gameplay, UI или конкретных player rules.

## 5. Классификация нового кода

Каждый существенный новый network/distributed component следует рассматривать как одну из категорий:

```text
A. GENERIC NETWORK CORE
B. SIMULATOR ADAPTER
C. RESEARCH / EXPERIMENT HARNESS
D. TEST / VALIDATION INFRASTRUCTURE
```

### A. Generic Network Core

Сюда относятся общие mechanics:

- identity / AuthorityId / EntityId;
- AuthorityEpoch / ownership fencing;
- OperationId / TransferId / replay protection;
- handoff state machine;
- topology / routing / directory semantics;
- leases / durable proofs / recovery;
- replication / snapshots / deltas;
- prediction / reconciliation / interpolation;
- transport abstraction / sessions;
- reference-frame transport/composition primitives;
- projection sequencing / interest primitives;
- network-condition simulation;
- observability / fault injection.

Предпочтительная incubation boundary для production-ready generic code — `scripts/network/`, если это не конфликтует с текущим ownership/roadmap.

### B. Simulator Adapter

Adapter связывает generic network runtime с конкретной доменной моделью симулятора. Он может знать одновременно о network contracts и simulator domain. Generic network code не должен зависеть обратно от adapter.

### C. Research / Experiment Harness

SM0 и аналогичные labs могут намеренно содержать fixture-specific значения вроде `authority/sm0/a`, `zone/earth/...`, `player/a`, `ship/01`. Research harness не обязан немедленно становиться generic.

После acceptance research branch является evidence/contract/semantic donor, но не обязан напрямую становиться production framework implementation.

### D. Test / Validation Infrastructure

Fault injection, latency/loss/reorder simulation, crash/restart runners, soak, invariant analyzers и evidence generators по возможности должны тестировать generic contracts через стабильную границу, а не через случайные внутренние поля simulator.

## 6. Naming и payload ownership

В новом reusable network code следует предпочитать generic identifiers:

```text
entity_id
authority_id
authority_epoch
source_authority_id
target_authority_id
region_id
reference_frame_id
operation_id
transfer_id
state_revision
snapshot
payload
```

Domain-specific имена допустимы в adapters, gameplay и research fixtures.

Network runtime определяет:

```text
WHO owns state
WHERE it is routed
WHEN ownership changes
WHICH epoch/revision is valid
WHETHER operation is replay/stale
WHETHER transfer committed/recovered
```

Domain code определяет:

```text
WHAT the state means
HOW gameplay mutates it
WHETHER a gameplay action is allowed
```

Network layer не должен интерпретировать item quantity, recipes, genetics, construction cost, inventory stacking или другие gameplay semantics.

## 7. Transfer / handoff direction

Новые generic transfer/handoff механизмы по возможности строить вокруг envelope + adapter-owned/opaque payload.

Целевая conceptual model:

```text
TransferEnvelope
{
    entity_id
    source_authority_id
    target_authority_id
    source_epoch
    target_epoch
    state_revision
    payload
    payload_hash
}
```

Framework-level protocol проверяет ownership/routing/revision/envelope. Simulator adapter проверяет domain payload.

Это направление для нового кода, а не требование немедленно переписать существующие принятые contracts.

## 8. Единая authority model

Нельзя без отдельного архитектурного решения создавать несовместимые authority models для player, item, ship, physics island, region, Construction или Ecology.

Разные domains могут иметь разные adapters и policy, но фундаментальные concepts должны по возможности переиспользовать:

```text
AuthorityId
AuthorityEpoch
Ownership
Transfer
Retirement
Activation
Replay fencing
Revision fencing
```

Новый вариант должен сначала классифицироваться как extension общей authority model или domain-specific policy поверх неё.

## 9. Transport и Godot independence

Высокоуровневые authority/handoff/recovery semantics не должны без необходимости зависеть от конкретного транспорта.

Целевое направление:

```text
Authority / replication protocol
        |
Transport interface
        |
UDP / ENet / loopback / future transport
```

GDScript/Godot остаётся допустимой текущей реализацией. Engine-neutral rewrite сейчас не требуется.

Но pure contracts/state algorithms по возможности не должны зависеть от scenes, graphical Nodes, UI, input actions или конкретных gameplay scenes. Не переписывать рабочий Node-based код только ради этого принципа без отдельного Work Order.

## 10. Contract discipline

Новые canonical network contracts по возможности должны иметь:

- explicit schema/version;
- exact field validation;
- deterministic serialization/hash;
- explicit ownership epoch;
- explicit state revision;
- replay-safe operation identity;
- fail-closed validation;
- deterministic error codes.

Изменение уже принятого contract проходит обычный compatibility/review процесс.

## 11. Configuration over hardcoding

В production/generic code topology, authority и routing data предпочтительно получать через configuration/provider/registry/directory/adapter.

Hardcoded `AUTHORITY_A`, `Earth West`, `ship/01` и подобные значения остаются допустимыми в research harnesses, fixtures и deterministic focused tests.

## 12. Research donor rule

Принятый research branch следует использовать как:

```text
evidence donor
contract donor
semantic donor
```

После acceptance необходимо переносить доказанные semantics в актуальную product/network architecture, а не blindly merge stale research implementation в текущую product line.

Особенно это относится к SM0: frozen lab должен сохранять воспроизводимость evidence и не становиться вторым gameplay/network truth.

## 13. No refactor without current value

Framework-readiness сама по себе не является основанием для большого refactor.

Refactor внутри текущего Work Order допустим, если он одновременно нужен для correctness, capability, устранения реального duplication, required testability, снижения operational risk или прямо разрешён Work Order.

Иначе extraction откладывается.

## 14. Tests

Зрелый generic mechanism по возможности должен иметь два уровня проверки:

```text
generic contract/unit/process test
+
simulator integration test
```

Generic test желательно формулировать через `entity X`, `authority A/B`, epochs, revisions и snapshots, а gameplay-specific сценарии оставлять integration layer.

## 15. Framework extraction readiness

Код особенно хорошо подготовлен к будущему выделению, если:

1. `scripts/network` не импортирует simulator-specific gameplay domain без необходимости;
2. topology/configuration передаётся извне;
3. entity state проходит через adapter/payload contract;
4. canonical generic protocol не содержит Earth/ship/player-a assumptions;
5. transport заменяем;
6. core semantics тестируются без полноценного simulator;
7. public contracts versioned and deterministic.

Это критерии направления, а не обязательный gate каждой текущей задачи.

## 16. Когда можно создавать отдельный framework repository

Не выделять отдельный repository до отдельного formal checkpoint.

Рекомендуемые prerequisites:

```text
A. stable network dependency boundary;
B. generic contracts без SM0/Earth/player-a/ship-01 assumptions;
C. simulator использует core через adapters;
D. самостоятельный network-core test suite;
E. минимум один второй example/consumer без simulator domain;
F. зрелая production validation authority/handoff/recovery semantics.
```

Перед extraction желательно иметь небольшой independent example consumer: несколько authorities и generic moving entities с handoff, restart, fault injection и projection, но без Item Graph, Construction, Matter и Ecology.

## 17. Reviewer rule

Reviewer не должен требовать generic abstraction только ради будущего framework.

Но как architectural concern следует отмечать случаи, когда новый generic-looking component без необходимости:

- импортирует simulator gameplay domain;
- создаёт новую authority truth;
- hardcodes product topology в production core;
- смешивает transport и gameplay semantics;
- создаёт второй authoritative store;
- существенно усложняет будущую extraction.

Severity определяется текущим Work Order и реальным риском.

## 18. Implementer reporting

Для крупных network Work Order в итоговом отчёте желательно указывать:

```text
Framework impact:
- generic core changed: YES/NO
- simulator adapter changed: YES/NO
- research-only code changed: YES/NO
- new simulator -> network dependency: ...
- new network -> simulator dependency: ...
```

## 19. Protected development flow

Эта policy не отменяет и не ослабляет exact SHA discipline, branch/worktree isolation, Work Orders, independent review, Project Control, acceptance gates, runtime verification, checkpoint discipline, no-self-acceptance rules и существующие V0/NX/SM roadmap.

При конфликте current approved Work Order и canonical Project Control имеют приоритет над speculative framework work.

## 20. Короткое правило для агента

Перед добавлением нового network code спросить:

```text
"Нужно ли этому алгоритму знать, что это именно Distributed World Simulator?"
```

Если `NO` — по возможности держать его generic.

Если `YES` — знание должно оставаться в simulator adapter/domain layer.

Если generic extraction требует существенного дополнительного scope — не делать extraction сейчас, сохранить возможность и выполнить текущую задачу.

## 21. Текущий стратегический статус

`scripts/network/` рассматривается как основной incubation boundary будущего reusable network runtime.

`scripts/runtime/seamless/sm0/` рассматривается прежде всего как research/reference/evidence environment.

Simulator-specific runtime является consumer/integration environment.

Основная цель сейчас: продолжать строить работающую сеть для Distributed World Simulator, одновременно не создавать лишние архитектурные связи, которые позже заставят переписывать её при выделении самостоятельного framework.
