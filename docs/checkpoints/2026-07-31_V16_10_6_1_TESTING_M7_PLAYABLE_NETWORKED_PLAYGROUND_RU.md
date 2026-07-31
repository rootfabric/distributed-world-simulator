# Checkpoint v16.10.6.1 — M7 Playable Networked Playground fix1

## Статус

```text
checkpoint: v16.10.6.1-testing-m7-playable-networked-playground
build_id: m7-playable-networked-playground
base: v16.10.6-architecture-a3-single-server-multiplayer
branch: feature/m7-playable-networked-playground
status: candidate
```

## Назначение

После принятия A3 добавлена отдельная игровая композиция для проверки реального пользовательского пути. Существующие M3/M5 acceptance-композиции сохранены.

M7 использует обычный `LunarPlayer`, существующий `ItemGameplayController`, профиль `seven_days_like`, 3D presentation и один authoritative `NetworkedGameplayService` на dedicated server.

## Исправления архитектурной проверки fix1

### Server-side movement

Графический клиент больше не передаёт готовые координаты. Он отправляет только `MOVEMENT_INTENT`: оси, sprint/jump, направление взгляда и ограниченный `delta_seconds`. Dedicated server рассчитывает canonical position, velocity, orientation и interaction origin. Входящий `PLAYER_STATE` отклоняется.

### Server-side spatial item validation

Pickup проверяет authoritative distance и deterministic server visibility. Drop/place не принимают клиентский transform: сервер строит ограниченный transform перед игроком. Таким образом нельзя подобрать предмет из произвольной точки или разместить его по координатам, присланным модифицированным клиентом.

### M6 recovery для 10-слотового hotbar

`playable_sandbox` извлекается из durable snapshot до валидации Item Graph. Отдельный процессный тест выполняет mutation → stop/kill → новый server process → restore → reconnect → continued movement/drop. Hotbar размером 10 и slot 9 восстанавливаются, ownership epoch повышается `1 → 2`.

## Реализованный вертикальный срез

- обычный InputMap и mouse-look intent;
- server-side character movement;
- remote player presentation;
- server-validated pickup/drop/place;
- установка монтажного основания;
- mount/detach маяка;
- общий внешний контейнер;
- inventory/hotbar через Seven Days UI;
- M6 persistence и recovery dedicated authority;
- отдельные launch/stop scripts;
- graphical two-client process acceptance.

## Дополнительное convergence hardening

После Item Graph mutation сервер публикует обновлённый player snapshot metadata. M5 convergence lock снимается при поздней canonical revision до общего `finish`, но остаётся зафиксированным после финального барьера.

## Приёмка fix1

Проверено на `Godot 4.7.1 stable.double`, commit `a13da4feb8d8aefc283c3763d33a2f170a18d541`:

```text
Editor import:                         PASS
Focused M7:                            13/13 PASS
M7 integration/security:               50 assertions, 0 failures
M7 graphical two-client process:       28 assertions, 0 failures
M7 restart/reconnect recovery:          36 assertions, 0 failures
M5 graphical acceptance regression:    93 assertions, 0 failures
Network/runtime:                       63/63 PASS
World/core regression:                108/108 PASS
Manifest coverage:                    108/108 PASS
Main scene CLI:                        6/6 PASS
```

Ручной сценарий и ограничения описаны в `docs/testing/M7_PLAYABLE_NETWORKED_PLAYGROUND_RU.md`.
