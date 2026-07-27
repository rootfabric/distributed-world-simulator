# Терминология сетевой архитектуры PlanetSimulator

## Authority

Право изменять canonical state. Для одной entity/island в один tick существует один authority.

## Authority lease

Ограниченная по времени аренда authority с `owner_node_id` и `epoch`.

## Authority epoch

Монотонный fencing token. Сообщение со старой эпохой не может изменить состояние.

## AuthorityRegion

Динамическая группа стабильных partition cells, рассчитываемая одним simulation node.

## PartitionCell

Стабильный адрес хранения и spatial lookup. Не равен серверу.

## SimulationSpace

Логическое пространство с frame, boundary и simulation policy: Sol, Moon surface, cave, ship interior.

## InteractionIsland

Связанная физическая/доменная группа, которую нельзя безопасно разрезать между authority nodes.

## Authority entity

Единственная изменяемая копия entity.

## Ghost

Read-only подробная копия на соседнем server для overlap/interaction.

## Projection

Упрощённое представление child/far space: bounds, aggregate state, крупные события.

## Directory stub

Минимальная запись route: entity, node, region, epoch, revision.

## Handoff

Транзакционная передача authority от source к target.

## Make-before-break

Target connection и candidate state подготавливаются до отключения source.

## InterestSet

Объекты, данные которых нужны клиенту или соседнему серверу.

## ActivationSet

Объекты, для которых выполняется дорогая локальная симуляция.

## Command envelope

Versioned network message, содержащий command, operation ID, expected revision и authority epoch.

## Snapshot

Полное сериализуемое состояние aggregate/entity в конкретный simulation tick.

## Delta

Изменения относительно известной base revision/snapshot.

## Grace period

Интервал после commit, когда source хранит read-only ghost для сглаживания перехода.

## Fencing

Отклонение сообщений старого authority через epoch/revision.
