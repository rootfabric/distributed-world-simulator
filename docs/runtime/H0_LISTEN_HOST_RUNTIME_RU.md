# H0 — listen-host runtime

**Checkpoint:** `v16.8.0-runtime-h0-listen-host`
**Build ID:** `h0-single-process-network-first-host`
**Branch:** `feature/h0-listen-host-runtime`

## Цель

H0 добавляет первый однопроцессный network-first host. Authority и client находятся в одном Godot-процессе, но клиентская сторона не получает authoritative aggregates, registries или domain services. Команды и репликация проходят через существующие DTO и canonical JSON round-trip boundary.

```text
ListenHostRuntime
├── N1RemoteItemAuthority
├── loopback command transport
└── ClientRuntime
    ├── ClientCommandGateway
    └── ClientReplicaStore
```

## Реализованные компоненты

- `scripts/runtime/listen_host/listen_host_runtime.gd` — composition root;
- `scripts/runtime/listen_host/client_runtime.gd` — клиентская runtime-граница;
- `scripts/runtime/listen_host/client_command_gateway.gd` — отправка `NetworkCommandEnvelope` только из replica state;
- `scripts/runtime/listen_host/client_replica_store.gd` — snapshot/delta replica;
- `scripts/runtime/listen_host/listen_host_authority_gateway_adapter.gd` — server-side adapter;
- `scripts/network/session/n1_deterministic_item_id_generator.gd` — детерминированная N1/H0 fixture identity для сравнения transport paths.

## Главный сценарий

```text
initial authoritative snapshot
→ canonical loopback replication
→ ClientReplicaStore
→ item.move_to_container command from replica
→ canonical loopback command transport
→ authoritative mutation
→ EntityDeltaEnvelope
→ ClientReplicaStore
→ exact command replay
→ duplicate delta fence
→ stale revision rejection
```

Итоговый snapshot checksum в H0 обязан совпасть с реальным N1.2 ENet server/client процессом при одинаковой fixture identity, authority owner/epoch и server tick.

## Fences

H0 проверяет:

- клиент не хранит ссылку на authoritative aggregate;
- snapshot accessors возвращают глубокие копии;
- loopback transport выполняет canonical JSON round-trip;
- presentation/client state читается только из replica;
- exact `operation_id` replay не вызывает вторую mutation;
- повторная delta не применяется второй раз;
- stale revision отклоняется;
- client/server final checksums совпадают;
- loopback/ENet final checksums совпадают.

## Runtime role

Добавлена роль:

```text
listen-host
```

Её политика:

```text
presentation_enabled: true
local_input_enabled: true
authoritative: true
client_replica_enabled: true
embedded_authority: true
direct_client_domain_access_allowed: false
```

`SimulatorApp` создаёт H0 composition root при `--role=listen-host`. Обычный F5 пока остаётся `offline`: перенос существующего gameplay UI на `ClientReplicaStore` выполняется отдельными последующими vertical migrations, а не скрытым прямым переключением всего проекта.


## Test profile

```text
H0 contract assertions:       71
H0 process assertions:        24
Network suites:               25/25
Network assertions:           2136/2136
World scripts:                68/68
Main scene offline/listen-host: 6/0 each
```

## Что намеренно не входит

- generic aggregate foundation;
- несколько peers;
- NATS/message bus;
- Population Field;
- полная миграция существующего inventory UI;
- World Directory;
- замена default F5.

## Следующий этап

`A1 — Generic Aggregate Foundation`.
