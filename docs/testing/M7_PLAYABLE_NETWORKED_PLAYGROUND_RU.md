# M7: полноценный сетевой полигон

M7 — отдельная ручная и автоматизированная композиция поверх принятого A3. Она не заменяет M3/M5 acceptance-сцены и запускается только с флагом `--network-playground`.

## Назначение

Сборка проверяет обычный игровой путь, но не передаёт клиенту владение состоянием:

```text
InputMap и мышь
→ MOVEMENT_INTENT / ITEM_COMMAND через ENet
→ один NetworkedGameplayService на dedicated server
→ server-side movement + spatial item validation
→ authoritative player snapshot и Item Graph
→ replica клиента
→ существующий Seven Days UI и 3D presentation
```

Клиент не отправляет готовые `position`, `velocity`, `basis` или `interaction_position`. Сервер рассчитывает движение, хранит каноническое положение игрока и использует его для проверки предметных команд.

## Серверная authority-модель

- `MOVEMENT_INTENT` содержит оси движения, sprint/jump, направление взгляда и ограниченный шаг времени.
- Dedicated server рассчитывает position, velocity, orientation и interaction origin.
- `PLAYER_STATE` от графического клиента отклоняется с `CLIENT_AUTHORITATIVE_STATE_FORBIDDEN`.
- Pickup разрешается только в пределах authoritative interaction range и server-side visibility ray.
- Drop и place игнорируют клиентский transform: сервер строит ограниченный transform перед игроком.
- Sandbox-режим извлекается из durable snapshot до валидации Item Graph, поэтому hotbar на 10 слотов восстанавливается после перезапуска.

## Быстрый запуск на Windows

```powershell
.\PLAY_M7_NETWORKED_PLAYGROUND.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" `
  -ClientCount 2
```

Скрипт запускает один headless dedicated server и два обычных графических окна. Каждый процесс получает изолированный `user://`, поэтому настройки и MCP-порты клиентов не конфликтуют.

Остановка:

```powershell
.\STOP_M7_NETWORKED_PLAYGROUND.ps1
```

Сброс сохранённого authoritative состояния перед запуском:

```powershell
.\PLAY_M7_NETWORKED_PLAYGROUND.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" `
  -ResetPersistence
```

## Управление

| Действие | Управление |
|---|---|
| Захват мыши | клик по игровому viewport |
| Движение | `WASD` |
| Бег | `Shift` |
| Прыжок | `Space` |
| Инвентарь | `Tab` |
| Подобрать / открыть / установить | `E` |
| Выбросить выбранный предмет | `G` |
| Фонарик | `F` |
| Быстрая панель | `1–0` |
| Системное меню | `Esc` |

На полигоне находятся общий маяк, руда, контейнер и монтажное основание. В стартовом инвентаре каждого игрока есть маяки, монтажные основания и батарея.

## Что проверять вручную

1. Оба игрока видят рассчитанные сервером перемещения друг друга.
2. Попытка подобрать далёкий предмет не проходит; после подхода и взгляда на цель pickup проходит у сервера.
3. Один игрок подбирает физический предмет; у второго он исчезает из мира и появляется в authoritative инвентаре владельца.
4. Предмет выбрасывается из hotbar рядом с authoritative положением игрока и появляется одинаково у обоих клиентов.
5. Монтажное основание устанавливается сервером в допустимой точке перед игроком.
6. Маяк монтируется в основание и снимается обратно в инвентарь.
7. Контейнер появляется в UI только после взаимодействия `E`; размер слотов совпадает с authoritative container state.
8. После остановки или аварийного завершения dedicated server новый процесс восстанавливает 10-слотовый hotbar, Item Graph и player entity; reconnect повышает ownership epoch и игра продолжается.

## Автоматическая проверка recovery

`test_m7_playable_networked_recovery_processes.gd` выполняет полный процессный сценарий:

```text
server generation 1
→ движение через intent
→ pickup и запись предмета в hotbar slot 9
→ stop/kill
→ server generation 2 с тем же PersistenceRoot
→ durable restore hotbar 10/10
→ reconnect ownership epoch 1 → 2
→ движение и drop после recovery
→ проверка, что malicious client transform 9000/9000/9000 проигнорирован
```

## Диагностика

Активная сессия:

```text
artifacts/runtime/m7-network-playground-active.json
```

Логи конкретного запуска:

```text
artifacts/runtime/m7-network-playground/<UTC timestamp>/
```

Состояние persistence:

```text
artifacts/runtime/m7-network-playground-persistence/
```

## Ограничения кандидата

M7 использует простой серверный интегратор движения для тестового полигона. Client-side prediction, rollback, lag compensation, полноценные серверные столкновения с динамической геометрией, искусственная задержка и packet-loss профили остаются отдельными этапами. Клиент при этом уже не является автором канонических координат или предметных transform.
