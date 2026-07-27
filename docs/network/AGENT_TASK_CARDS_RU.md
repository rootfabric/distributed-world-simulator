# Карточки маленьких задач для агентской разработки сети

Каждая карточка должна выполняться отдельным патчем.

## NET-000 — Network schema registry

**Размер:** S

Создать:

```text
scripts/network/contracts/network_schema_registry.gd
tests/network/test_network_schema_registry.gd
```

Проверки:

- регистрация schema;
- duplicate schema rejection;
- unknown version rejection;
- canonical JSON.

Не открывать сокеты.

## NET-001 — Command envelope

**Размер:** S

Создать `NetworkCommandEnvelope` поверх существующих operation/revision контрактов.

Acceptance:

- 1000 JSON round-trips;
- hash стабилен;
- старый epoch rejected;
- нет Variant runtime references.

## NET-002 — Entity snapshot envelope

**Размер:** S

Поддержать:

```text
entity record
SpatialRef
item graph reference/full aggregate
revision
authority
simulation tick
```

Acceptance: snapshot загружается в новый domain runtime и имеет тот же checksum.

## NET-003 — Server role bootstrap

**Размер:** S

CLI:

```text
--role=simulation-server
--node-id
--listen-port
--instance-id
--report-path
```

Acceptance: headless процесс печатает `node_ready` и завершается по команде.

## NET-004 — ENet transport adapter

**Размер:** M

Без gameplay logic. Реализовать connect, disconnect, send envelope, receive envelope.

Acceptance: echo round-trip между двумя процессами.

## NET-005 — Single authority item move

**Размер:** M

Client переносит маяк через server command.

Acceptance:

- client не мутирует domain;
- server revision +1;
- duplicate operation не меняет state;
- snapshots совпадают.

## NET-006 — Python process harness

**Размер:** M

Acceptance:

```text
pytest запускает server/client
ждёт node_ready
выполняет сценарий
убивает процессы
создаёт junit.xml
```

## NET-007 — In-memory directory

**Размер:** M

Node registration, heartbeat, static routes.

Acceptance: два simulation nodes получают разные static regions.

## NET-008 — Authority lease

**Размер:** M

Acceptance:

- единственный owner;
- renew;
- expiration;
- epoch fencing;
- concurrent acquire.

## NET-009 — Handoff state machine pure test

**Размер:** S

Не использовать сеть. Проверить все переходы и abort branches.

## NET-010 — Object handoff happy path

**Размер:** M/L

Stone переходит A → B. Допускается pause.

Acceptance: no duplicates, checksum, position/velocity continuity.

## NET-011 — Handoff crash matrix

**Размер:** L

Автоматически убивать source/target на каждой стадии.

Acceptance: после каждой аварии существует ровно один authority или явно зафиксированное safe-unowned recovery состояние.

## NET-012 — Dual connection bot

**Размер:** M

Client bot держит primary и warm peers.

Acceptance: promote without full process reconnect.

## NET-013 — Player handoff

**Размер:** L

Acceptance: 100 crossings, input and inventory conservation.

## NET-014 — Ghost replica

**Размер:** M

Acceptance: read-only, TTL, stale revision ignored.

## NET-015 — Network fault profiles

**Размер:** M

Добавить netem/Toxiproxy wrappers и параметризованные tests.

## NET-016 — Docker Compose lab

**Размер:** M

Поднять directory, sim-a, sim-b, bot. Все зависимости только по healthcheck.

## NET-017 — Moon cave child space

**Размер:** L

Surface ↔ cave handoff через portal.

## NET-018 — Static Earth region mapping

**Размер:** L

Стабильные cube-sphere cells группируются в static authority regions.

## NET-019 — Interaction island descriptor

**Размер:** M

Ship + cargo + players + attachments определяются как единая мигрируемая группа.

## NET-020 — Soak runner

**Размер:** M

10 000 object handoff с memory/entity/epoch assertions.
