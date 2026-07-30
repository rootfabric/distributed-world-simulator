# M3 — Dedicated server + два графических клиента

**Checkpoint:** `v16.10.2-runtime-m3-dedicated-graphical-multiplayer`
**Build ID:** `m3-dedicated-two-graphical-clients`
**База:** принятый `v16.10.1-runtime-m2-dedicated-graphical-client`
**Статус:** candidate

## Цель

M3 расширяет M2 до одной authoritative region с двумя одновременно подключёнными обычными окнами Godot:

```text
Process 1: Godot --headless --role=dedicated-server
Process 2: graphical Godot --role=game-client --player-identity=a
Process 3: graphical Godot --role=game-client --player-identity=b
```

Dedicated server остаётся единственным владельцем `NetworkedGameplayService`. Оба клиента содержат только ENet transport, command gateway, replica state и presentation.

## Local и remote player

На каждом клиенте создаются разные presentation-типы:

```text
local logical player  → настоящий LunarPlayer + Camera3D + local input
remote logical player → RemotePlayerPresenter без input authority
```

`RemotePlayerPresenter` получает из replica:

- authoritative position и velocity;
- `orientation_yaw`;
- `flashlight_enabled`;
- connected/disconnected state;
- player entity identity и state revision.

Позиция удалённого игрока интерполируется только на render-слое. Интерполяция не изменяет canonical state и не создаёт client authority.

## Репликация и жизненный цикл

`LunarApp` отслеживает полный `PlayerStateSnapshot`:

- connected remote player создаёт presenter;
- snapshot/delta обновляет target transform, orientation и flashlight;
- leave/disconnect удаляет presenter;
- reconnect той же logical identity создаёт presenter заново;
- local player никогда не представляется через `RemotePlayerPresenter`.

Для presentation state добавлена versioned команда `PlayerPresentationCommand` и событие `PLAYER_PRESENTATION_UPDATED`. DTO и checksum остаются JSON-safe и implementation-independent.

## Автоматическая graphical acceptance

`test_m3_graphical_multiplayer_processes.gd` запускает настоящий X11/GL process-сценарий. Клиенты стартуют последовательно для устойчивой загрузки мира, но после запуска B работают одновременно до завершения взаимной репликации.

Сценарий:

```text
server READY
→ A joins
→ B joins, пока A остаётся подключён
→ A и B получают remote presenters
→ A moves, B observes
→ B moves, A observes
→ A включает flashlight, B подтверждает presentation delta
→ A leaves
→ B despawns A и продолжает authoritative movement
→ A reconnects как player/a с ownership epoch 2
→ B respawns A
→ server, A и B фиксируют один checksum
→ все клиенты выполняют graceful leave
```

Presentation и convergence используют явные barriers. A не отключается, пока B не подтвердит получение orientation/flashlight state. Финальный checksum фиксируется до graceful leave, чтобы leave delta не создавал ложное расхождение отчётов.

Каждый server/client phase получает отдельные `HOME`, `XDG_*`, `APPDATA` и `LOCALAPPDATA`. Process test отклоняет журналы с `ObjectDB instances leaked` или `resources still in use`.

## Закрытие M2 gates

- **M2-G01:** validation metadata зафиксирована как 70 assertions и 1052 focused assertions для принятой M2-поставки.
- **M2-G02:** M2 contract nodes освобождаются явно; M3 graphical process проверяет чистый shutdown по логам.
- **M2-G03:** M3 focused/process и общий world runner используют изолированные user profiles.

## Граница M3

M3 доказывает graphical multiplayer presentation, но ещё не переносит полный канонический H1 Item Graph в двухклиентский ENet gameplay. Pickup/drop/stack/split, контейнеры, mount/detach и item contention закрываются M4. Полный graphical gameplay acceptance относится к M5, recovery dedicated server — к M6.
