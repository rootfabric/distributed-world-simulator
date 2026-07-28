# Терминология сетевой и распределённой архитектуры PlanetSimulator

## Canonical state

Единственное официальное доменное состояние. Presentation, client replica, ghost и worker input не являются canonical state.

## Authority

Право изменять canonical state. Для одного aggregate/shard в один момент существует один authoritative writer.

## Authority lease

Ограниченная по времени аренда authority с owner, epoch, scope и сроком действия.

## Authority epoch

Монотонный fencing token. Сообщение со старой эпохой не может изменить состояние.

## AuthorityAddress

Маршрут к текущему authoritative writer. Не обязан совпадать со spatial address или process location.

## AuthorityRegion

Набор spatial scopes или shards, временно обслуживаемый одним Region Authority. Не является постоянной частью identity мира.

## Aggregate

Authoritative consistency boundary с устойчивым ID, kind, state schema, revision, tick, authority metadata, snapshot и persistence adapter.

## Aggregate kind

Категория aggregate с отдельной schema/validator, например `WORLD_ITEM`, `POPULATION_FIELD`, `ENVIRONMENT_CELL` или `PROCESS`.

## Aggregate shard

Физически независимо versioned и owned часть большого logical object.

## Entity

Индивидуальный объект мира. Для point-like objects используется `EntitySnapshotEnvelope`; entity может быть одним из aggregate kinds.

## Population field

Агрегированное представление большой популяции: seed, cohorts, patch states, exclusions и materialized exceptions вместо entity на каждый visual instance.

## Cohort

Группа близких по типу/варианту/состоянию организмов внутри population field.

## Procedural instance key

Детерминированный ключ visual instance, вычисляемый из field, patch, index и generation. Позволяет материализовать конкретный экземпляр.

## Materialization

Атомарный переход procedural/population representation в индивидуальный aggregate.

## EntityPartGraph

Стабильно адресуемый граф частей сложной сущности. Отделённая часть может стать самостоятельным aggregate.

## SpatialAddress

Каноническое положение или spatial scope объекта в Universe/Instance/Space/Region/Cell hierarchy.

## SimulationCell

Стабильная spatial indexing и job partition unit. Не равна server process или authority owner.

## PartitionCell

Стабильный адрес хранения и spatial lookup в существующей partition system. Не равен серверу.

## SpatialScope

Описание охвата aggregate: point, bounds, cell, cell set, region или none.

## SimulationSpace

Логическое пространство с frame, boundary и simulation policy: Sol, Moon surface, cave, ship interior.

## InteractionIsland

Связанная физическая/доменная группа, которую нельзя безопасно разрезать между authority nodes в текущем tick.

## ClientRuntime

Клиентская application-композиция: input, command gateway, replica store и presentation. Не владеет authoritative aggregates.

## ClientReplicaStore

Клиентское read-model состояние, построенное только из validated snapshots/deltas.

## Listen-host

Один процесс, содержащий Region Authority и ClientRuntime, разделённые loopback DTO boundary.

## Local dedicated

Отдельные server/client процессы на одной машине, обычно связанные ENet localhost.

## Runtime topology

Описание того, какие логические runtime-компоненты embedded, process-local или remote и какими adapters они соединены.

## Transport listener lifecycle

Состояние transport endpoint: stopped, starting, listening, draining, failed.

## Peer session lifecycle

Состояние отдельного peer: connecting, transport-connected, handshaking, synchronizing, ready, draining, closed, failed.

## TransportSessionId

Identity конкретного transport connection. Меняется после reconnect.

## LogicalSessionId

Identity логической client/server session, которая может переживать смену transport connection.

## ReplicationTransportPort

Semantic port для snapshots, deltas, ghosts и interest updates.

## ServiceRequestReplyPort

Semantic port для discovery, Directory queries, health и route lookup.

## EventStreamPort

Semantic port для durable domain events и audit stream.

## JobQueuePort

Semantic port для simulation/background jobs с retry/ack semantics.

## BulkTransferPort

Semantic port для large snapshots, content packages и checkpoint transfer.

## Transport adapter

Конкретная реализация semantic port: loopback, ENet, NATS Core, JetStream, HTTP или другой механизм.

## Protocol frame

Transport-level envelope с session, sequence, channel, delivery mode, payload schema и checksum.

## NATS subject

Adapter-specific route. Не является canonical aggregate/entity identity и не сохраняется в domain state.

## Outbox

Durable запись сообщения/события, сохранённая атомарно вместе с authoritative commit и публикуемая асинхронно.

## Simulation Worker

Read-only compute process, который получает immutable job и возвращает proposal. Не является authority.

## SimulationJob

Самодостаточное задание с target IDs, tick range, input hashes, expected revisions, package versions и budgets.

## MutationProposal

Результат worker calculation с base revisions/tick, read/write sets, operations и result hash. Не является готовым authoritative state.

## MutationBatch

Атомарный набор create/update/delete операций над одним или несколькими aggregates.

## Read set / Write set

Декларация данных, которые rule/job читает и может изменить. Используется scheduler и authority validator.

## Compute assignment

Назначение worker для расчёта. Не меняет authority ownership.

## Ghost

Read-only подробная копия на соседнем server для overlap/interaction.

## Projection

Упрощённое представление child/far space: bounds, aggregate state, крупные события.

## Directory

Сервис регистрации nodes/services, leases и transport-neutral authority routes.

## Handoff

Транзакционная передача authority от source к target.

## Make-before-break

Target connection и candidate state подготавливаются до отключения source.

## InterestSet

Объекты и aggregates, данные которых нужны клиенту или соседнему серверу.

## ActivationSet

Объекты и aggregates, для которых выполняется дорогая локальная симуляция.

## Command envelope

Versioned message, содержащий command, operation ID, expected revision и authority epoch.

## Snapshot

Полное сериализуемое состояние aggregate/entity в конкретный simulation tick.

## Delta

Изменения относительно известной base revision/snapshot.

## Grace period

Интервал после handoff commit, когда source хранит read-only ghost для сглаживания перехода.

## Fencing

Отклонение stale сообщений через authority epoch, revision, tick, lease или session checks.
