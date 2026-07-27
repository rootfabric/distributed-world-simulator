# ADR-005: сетевой стек и границы протокола

**Статус:** предложено к принятию
**Дата:** 2026-07-27

## Контекст

PlanetSimulator должен локально тестировать несколько Godot simulation nodes и позднее перейти к server mesh. При этом канонический мир не должен зависеть от SceneTree replication или конкретного backend.

## Решение

1. Первый realtime transport — Godot `ENetMultiplayerPeer`.
2. Client и simulation server используют один проект и versioned domain DTO.
3. `SceneMultiplayer`/RPC не являются каноническим протоколом.
4. DTO имеют canonical JSON fixtures и schema version.
5. Python + pytest управляет multi-process тестами.
6. NATS/JetStream добавляется позднее только в control plane.
7. Nakama может обслуживать identity/lobby, но не authority handoff.
8. netfox оценивается позднее для prediction/interpolation, не для World Directory.
9. Agones добавляется после локально работающего handoff.

## Последствия

Плюсы:

- минимальная зависимость на старте;
- официальная Godot документация;
- одинаковый double build на server/client;
- понятные агентам fixtures;
- возможность заменить transport.

Минусы:

- часть replication logic пишется вручную;
- нужен собственный interest и handoff;
- ENet protocol связывает realtime edge с Godot;
- production control plane требует отдельного компонента.
