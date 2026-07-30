# M4 → M5: актуальная handoff-граница

Этот документ описывает фактическую рабочую базу `main` перед M5. Он дополняет
исторический checkpoint `v16.10.3-domain-m4-canonical-shared-gameplay` и
расширение сетевого полигона; он не создаёт новый gameplay path и не заменяет
M4 architecture document.

## База для M5

```text
canonical M4 checkpoint: v16.10.3-domain-m4-canonical-shared-gameplay
main integration: M4 networked playground + MCP runtime control
post-M4 fixes: movable graphical client window + camera-relative input
next stage: M5 — Graphical Multiplayer Acceptance
```

M5 начинает работу от `main`. В него уже входят M1–M4, UI-профили inventory,
испытательный полигон и MCP-инструментирование. Новый M5 код не должен
создавать отдельную authority, отдельный Item Graph или второй transport path.

## Зафиксированная topology

```text
headless dedicated server
  └─ NetworkedGameplayService (единственная gameplay composition root)
       ├─ Player ownership + player-state replication
       └─ CanonicalMultiplayerItemGraphService
              └─ revision, tick, authority epoch, checksum, replay ledger

graphical client A / graphical client B
  └─ ENet replica only
       ├─ local player presentation and camera-relative input
       ├─ RemotePlayerPresenter for every remote player
       └─ Item Graph snapshot replica
```

Клиент не получает ссылок на server authority или domain objects. Он отправляет
`MOVE`, `PRESENTATION` и `ITEM_COMMAND` по ENet, применяет snapshots и
отображает их. Server остаётся единственным местом canonical mutation.

## Canonical Item Graph M4

Путь команды:

```text
graphical client
→ ITEM_COMMAND / ENet
→ M3DedicatedServerRuntime
→ NetworkedGameplayService
→ CanonicalMultiplayerItemGraphService
→ targeted COMMAND_RESULT
→ ITEM_GRAPH_SNAPSHOT всем connected clients
```

Поддерживаемые команды M4:

- `item.pickup`, `item.drop`, `item.split`, `item.stack`;
- `inventory.select_hotbar`;
- `container.open`, `container.close`, `item.move_to_container`;
- `item.mount`, `item.detach`;
- `inventory.permission_probe` для отрицательной проверки.

Проверяемые правила уже существуют и не должны дублироваться в UI:

- один item identity имеет ровно одно расположение;
- первый pickup shared beacon побеждает, второй получает `ITEM_ALREADY_CLAIMED`;
- изменение чужого inventory получает `PLAYER_PERMISSION_DENIED`;
- одинаковый operation ID с тем же payload replay-safe;
- тот же operation ID с иным payload получает `OPERATION_REPLAY_CONFLICT`;
- stale transport session и неверный ownership epoch отклоняются;
- checksum Item Graph должен совпасть у server, client A и client B.

Canonical fixture IDs для ручного и будущего UI acceptance:

```text
item/shared/beacon/1
item/shared/ore/1
item/shared/crate/1
container/shared/crate/1
mount/shared/socket/1
```

## Испытательный полигон

`playground` — основная ручная среда M5. Он использует ту же M3/M4 vertical,
что и process tests, а не локальную упрощённую authority.

На нём доступны:

- dedicated server + два одновременных graphical clients;
- ownership, spawn/despawn, reconnect и stable `player_entity_id`;
- remote-player interpolation, orientation и flashlight replication;
- authoritative movement;
- Item Graph replica и все M4 commands через тот же `ITEM_COMMAND`;
- developer-console adapter к canonical M4 API.

Существующие console-команды клиента:

```text
m4.item.pickup <item_id>
m4.item.drop <item_id> [quantity]
m4.item.split <item_id> <quantity>
m4.item.stack <source_item_id> <target_item_id>
m4.container.open <container_id>
m4.container.close <container_id>
m4.item.move_to_container <item_id> <container_id>
m4.item.mount <item_id> <mount_id>
m4.item.detach <mount_id>
m4.hotbar.select <0-7>
m4.snapshot
```

В M5 реальные inventory/container widgets должны вызывать этот же runtime API.
Console-команды остаются диагностическим адаптером, а не второй реализацией
gameplay.

## Inventory UI и interaction profiles

В `main` уже интегрирована UI-база inventory, которую M5 должен использовать,
а не заменять новым экраном. Каталог профилей находится в
`config/ui/inventory_profiles/catalog.json` и содержит:

- `planet_default` — исходное управление;
- `rust_like` — альтернативная схема жестов;
- `seven_days_like` — слотная раскладка и cursor-transfer interaction.

`InventoryInteractionProfileLoader` загружает профиль,
`InventoryInteractionRouter` интерпретирует жесты, а
`InventoryCursorController` представляет переносимый stack во временном
`UI_TRANSIENT` slot. Для `seven_days_like` уже определены take/place whole
stack, split half, place one, swap, Shift+click transfer и rollback при
отмене. Выбор профиля и layout являются local UI preference; они не меняют
ownership, authority или canonical Item Graph.

Критическая граница для M5: текущая UI-подсистема умеет отображать и
интерпретировать inventory interaction, но её действия должны быть связаны с
M4 `ITEM_COMMAND`/`COMMAND_RESULT`, а не с прямой локальной mutation. До
подтверждения server result UI не должна считать client-side projection
канонической.

## Окно, курсор и движение graphical client

Для ручного тестирования client запускается с видимым курсором. Поэтому окно
можно переместить за системный заголовок сразу после старта. Клик по viewport
штатно захватывает курсор для look input. Открытие inventory освобождает курсор
по текущему UI-контракту.

InputMap остаётся стандартным:

```text
W/S — вперёд/назад
A/D — влево/вправо
Shift — ускорение
Space — прыжок
```

В M3/M4 client path входной вектор сначала преобразуется базисом активной
камеры в horizontal `forward/right`, затем только его `x/z` передаются в
authoritative `MOVE`. Поэтому движение следует направлению взгляда, а не
фиксированным мировым осям. Wire contract `delta_x/delta_z` и server-side
movement validation от этого не менялись.

## MCP как инструмент разработки

`Breakpoint MCP` добавлен в проект как локальный loopback-инструмент:

- editor bridge: `127.0.0.1:9080`;
- runtime bridge: `127.0.0.1:9081`;
- double Godot binary: `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`.

MCP предназначен для запуска/наблюдения одного managed runtime, injection
ввода, SceneTree assertions, runtime logs и viewport screenshots. Он не
является network transport и не заменяет ENet. На одном порту `9081` может
работать только один runtime bridge; перед запуском следующего MCP-managed
runtime предыдущий нужно штатно остановить. Полный контракт и ограничения — в
[`MCP_GODOT.md`](../MCP_GODOT.md).

## Граница M5

M5 должна доказать пользовательский end-to-end путь в двух обычных игровых
окнах:

1. UI открывает inventory/container и формирует canonical M4 command.
2. Два клиента выполняют movement и item interaction через реальный input.
3. Contention, permission denial, disconnect/reconnect и presentation
   проверяются через видимое состояние UI и snapshots.
4. Server и оба клиента сходятся к одному Item Graph checksum.

M5 не включает persistence/crash recovery dedicated server (M6), новую
transport topology, NATS или distributed authority.

## Команды проверки перед M5

```powershell
.\RUN_M4_NETWORKED_PLAYGROUND_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_M4_CANONICAL_SHARED_GAMEPLAY_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_INVENTORY_PROFILE_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_NETWORK_CONTRACT_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_WORLD_REGRESSION_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Если пользователь уже держит живой graphical client для ручного теста, не
запускайте параллельно MCP-managed runtime на `9081`. Либо используйте этот
клиент для наблюдения, либо сначала завершите его штатно.

## Связанные документы

- [`M4_CANONICAL_SHARED_GAMEPLAY_RU.md`](M4_CANONICAL_SHARED_GAMEPLAY_RU.md) —
  архитектурная граница canonical Item Graph;
- [`2026-07-30_M4_NETWORKED_PLAYGROUND_EXTENSION_RU.md`](../checkpoints/2026-07-30_M4_NETWORKED_PLAYGROUND_EXTENSION_RU.md) —
  перенос vertical в `playground`;
- [`2026-07-30_V16_10_3_DOMAIN_M4_CANONICAL_SHARED_GAMEPLAY_RU.md`](../checkpoints/2026-07-30_V16_10_3_DOMAIN_M4_CANONICAL_SHARED_GAMEPLAY_RU.md) —
  историческая evidence M4;
- [`2026-07-30_INVENTORY_SEVEN_DAYS_PROFILE_RU.md`](../checkpoints/2026-07-30_INVENTORY_SEVEN_DAYS_PROFILE_RU.md) —
  slot/cursor interaction profile, доступный M5;
- [`M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md`](M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md) —
  presentation/ownership база;
- [`MCP_GODOT.md`](../MCP_GODOT.md) — контракт MCP tooling.
