# M4 Networked Playground Extension

```text
base: main @ 7f65563
branch: feature/m4-networked-playground-extension
status: candidate
```

## Цель

Расширение переносит принятую M3/M4 multiplayer-вертикаль в испытательный мир
`playground`, не создавая второй gameplay path.

На полигоне доступны:

- dedicated server и два одновременно подключённых graphical client;
- authoritative movement;
- local/remote player presentation;
- spawn, interpolation, despawn и reconnect;
- orientation и flashlight replication;
- canonical M4 Item Graph replica;
- M4 item-команды через тот же ENet `ITEM_COMMAND`;
- targeted command results, permission и ownership fencing;
- общий checksum server/client.

## Ручные M4-команды

В developer console клиента:

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

Canonical demo IDs:

```text
item/shared/beacon/1
item/shared/ore/1
item/shared/crate/1
container/shared/crate/1
mount/shared/socket/1
```

## Focused-проверка

```powershell
.\RUN_M4_NETWORKED_PLAYGROUND_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Process-проверка запускает настоящий dedicated server, два graphical client и
reconnect на `playground`.

## Граница

Это расширение сохраняет принятую границу M4. Canonical Item Graph доступен
через runtime API и developer console. Привязка canonical M4 snapshots к
полноценным inventory/container widgets игрового окна остаётся задачей M5
Graphical Multiplayer Acceptance.
