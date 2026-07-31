# A3 — Single-Server Multiplayer Architecture Freeze

```text
checkpoint: v16.10.6-architecture-a3-single-server-multiplayer
build_id: a3-single-server-multiplayer-architecture-freeze
base: v16.10.5-persistence-m6-dedicated-recovery
branch: feature/a3-single-server-multiplayer-architecture
status: accepted (delivery review-fix1)
resolution: SINGLE_SERVER_MULTIPLAYER_FROZEN
```

## Решение

После M1–M6 production single-server multiplayer фиксируется как одна семантическая система, а не набор реализаций для разных topology.

Единственным владельцем gameplay semantics является:

```text
scripts/runtime/networked_gameplay/networked_gameplay_service.gd
NetworkedGameplayService
```

Listen-host, compatibility H2/H3, dedicated ENet runtime и M6 recovery являются адаптерами транспорта, lifecycle или persistence. Они не имеют права владеть отдельными player/item registries, operation ledgers или альтернативными domain rules.

## Канонический путь

```text
Input/UI intent
→ client command gateway
→ versioned wire command
→ NetworkedGameplayService
→ authoritative mutation
→ durable commit, если persistence включён
→ targeted CommandResult + snapshot/delta
→ replica store
→ presentation
```

Graphical clients читают только validated replica state. Прямые ссылки клиента на authority, registry, repository, aggregate или live domain objects запрещены.

## Зафиксированное доказательство

- M1: общий `NetworkedGameplayService` и независимые wire validators.
- M2: один обычный graphical client против headless dedicated server.
- M3: два одновременно работающих graphical clients, local/remote presentation и reconnect.
- M4: полный canonical Item Graph поверх ENet и детерминированный contention.
- M5 fix1: UI-driven graphical acceptance, stable reconnect operation identity и convergence.
- M6 fix1: atomic dedicated checkpoint, crash/restart recovery, durable replay/outbox и ownership epoch после restart.

A2 debts `A2-D01`–`A2-D04` закрыты. `A2-D05` остаётся явным P2 debt: production authentication и trusted logical-player admission не входят в A3.

## Frozen wire contract family

A3 фиксирует одну versioned, JSON-safe, exact-field и Node-independent семью:

- `PlayerJoinCommand`;
- `PlayerLeaveCommand`;
- `PlayerInputCommand`;
- `PlayerPresentationCommand`;
- `PlayerOwnershipSnapshot`;
- `PlayerStateSnapshot`;
- `PlayerStateDelta`;
- `ItemCommand`;
- `ItemGraphSnapshot`;
- `ItemGraphDelta`;
- `CommandResult`.

Расширение контрактов допускается только версионированным checkpoint. Topology-specific DTO с альтернативной gameplay семантикой запрещены.

## B1 boundary

После независимой приёмки A3 следующий архитектурный этап — `v16.11.0-data-plane-b1-nats-core`.

B1 имеет только **server-to-server** scope через B0 semantic ports:

- discovery;
- heartbeat;
- health;
- load;
- capability discovery;
- request/reply;
- transport-neutral routing metadata.

B1 запрещено:

- заменять ENet для graphical realtime traffic;
- создавать второй gameplay command model;
- вызывать NATS напрямую из gameplay/domain кода;
- сохранять NATS subjects в canonical state;
- использовать broker delivery как authority ownership.

## Multi-authority gate

A3 не разрешает несколько authoritative world servers. Production N3 остаётся заблокирован до принятых A3, B1 и B2. B1/B2 обязаны добавить transport/delivery adapters без изменения single-writer gameplay semantics.

## Машинная проверка

```text
config/network/single-server-multiplayer-architecture.v1.json
scripts/runtime/networked_gameplay/a3/single_server_architecture_auditor.gd
tests/runtime/test_a3_single_server_multiplayer_architecture.gd
RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1
RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.sh
```

Обязательная приёмка также включает полный `RUN_NETWORK_CONTRACT_TESTS.ps1` и `RUN_WORLD_REGRESSION_TESTS.ps1`.

## Независимая приёмка

A3 принят 31 июля 2026 года, delivery `review-fix1`. Проверены focused A3 12/12, архитектурный контракт 140 assertions, полный Network/runtime, World regression и main scene CLI 6/6. Локальный acceptance archive SHA-256: `BAFC96B451220A1D1D12B4BD3FB9F1F0D130B1BA652A1F70AEAC0661B041A380`. M7 является отдельным playable validation checkpoint поверх принятой архитектуры и не изменяет B1 boundary.
