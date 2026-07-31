# Подготовка M5 — Graphical Multiplayer Acceptance

База: `main @ 2879fdb`.

Подготовительный checkpoint: `v16.10.3-pre-m5-graphical-acceptance-preparation`.
Эта подготовительная граница завершена и использована checkpoint-кандидатом M5. Его задача — связать уже принятый M4 Item Graph
с существующим inventory UI без второго gameplay path и подготовить стабильную
многопроцессную среду для будущей UI-driven приёмки.

## Замороженная граница

```text
inventory gesture / hotbar key
→ M5InventoryUiBridge
→ M4ItemCommandAdapter
→ ITEM_COMMAND / ENet
→ dedicated NetworkedGameplayService
→ canonical Item Graph mutation
→ COMMAND_RESULT + ITEM_GRAPH_SNAPSHOT
→ M4ItemGraphUiProjection
→ existing inventory widgets
```

Клиент не получает authority/domain references. Projection является read-only,
а cursor carry, drag preview и pending operations хранятся только в
`M4InventoryTransientState` и не входят в canonical checksum.

## Компоненты

- `M4ItemGraphUiProjection` — проверяет M4 schema/checksum/revision и создаёт
  модели `container_view.v2` для backpack, hotbar, external container, world
  items и mounts;
- `M4ItemCommandAdapter` — переводит UI aliases и slot context в точные M4
  commands, отбрасывая presentation-only поля;
- `M4InventoryTransientState` — cursor/pending overlay с нулём canonical
  mutations;
- `M5InventoryUiBridge` — соединяет M3/M4 client runtime с projection,
  command adapter и transient state;
- `M5NetworkedInventoryShell` — минимальная composition существующих
  `ContainerPanel` и `HotbarPanel` в networked playground;
- `M5ProcessEnvironment` — разные user-data roots и disabled/unique MCP runtime
  ports для server/A/B/reconnect процессов.

## Уже подготовлено

- Tab открывает replica-driven networked inventory в graphical client;
- hotbar keys отправляют `inventory.select_hotbar` через M4 runtime;
- external container появляется только после authoritative `container.open`;
- UI transfer в shared container переводится в `item.move_to_container`;
- item-on-item переводится в `item.stack`;
- mount UI aliases `assembly_id/socket_id` переводятся в canonical
  `item_id/mount_id`;
- stale/same-revision snapshots отклоняются;
- все M5 процессы могут отключить MCP bridge либо получить уникальный порт;
- общий `user://` не используется тестовым контуром.

## Честно оставшиеся gates полноценного M5

- reverse transfer из external container в inventory;
- assignment item identities в hotbar, а не только selection index;
- UI-driven pickup/drop/mount/detach из настоящего игрового viewport;
- полный seven-days cursor workflow поверх server acknowledgements;
- две одновременные graphical windows с реальным UI contention;
- automation через input/SceneTree/screenshot assertions;
- disconnect/reconnect в середине UI operation;
- финальный server/A/B checksum barrier после UI-driven сценария.

Все перечисленные gates закрыты в `v16.10.4-testing-m5-graphical-multiplayer-acceptance`; см. `M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`.
