# Аудит single-server multiplayer перед A3

Дата: 2026-07-31
Checkpoint: `v16.10.6-architecture-a3-single-server-multiplayer`

## Итог аудита

```text
production gameplay services: 1
production service: NetworkedGameplayService
authority adapters: 4
frozen wire contracts: 11
graphical realtime transport: ENet
durable recovery: M6 fix1 accepted
A2 P1 debts remaining: 0
multi-authority production: BLOCKED
B1 scope: SERVER-TO-SERVER ONLY
```

## Проверенные границы

1. Listen-host и dedicated ENet вызывают один `NetworkedGameplayService`.
2. M6 persistence адаптирует export/restore того же service и не создаёт отдельную gameplay model.
3. Graphical clients не preload-ят authority service, ownership service или recovery repository.
4. Wire contracts являются `RefCounted`, не зависят от `Node`, `SceneTree`, `Control` или `Camera3D`.
5. Canonical Item Graph identity и operation replay не зависят от topology adapter.
6. LOOPBACK и ENET с одинаковой командной последовательностью дают одинаковые player и Item Graph checksums.
7. Durable restore очищает transport sessions, сохраняет stable player entity и позволяет ownership epoch `1 → 2`.

## Закрытие исторических статусов

- M2 gates закрыты доказательствами M3/M5: process isolation и shutdown hygiene.
- M3 implementation manifest переведён из устаревшего `candidate` в `accepted`.
- M6 fix1 переведён в `accepted`; локальный архив acceptance имеет SHA-256 `7AF3317A3E2B9F24D452DECEC6A18D1AE0747A903F6C03A69DFFE0CC82B966BF`.
- `A2-D04` закрыт M6.

## Проверка кандидата на Godot double

```text
engine: Godot 4.7.1 stable.double custom build a13da4feb
A3 contracts: 140 assertions, 0 failures
Focused A3: 12/12 PASS
Network/runtime: 60/60 PASS, 4759 assertions
World regression: 105/105 PASS
Main scene CLI: 6/6 PASS
```

Независимая локальная приёмка завершена: A3 принят с delivery `review-fix1`; focused 12/12, контракт 140 assertions, полные Network/runtime и World regression подтверждены.

## Решение

A3 принят. B1 разблокирован только как adapter-only server-to-server этап; N3 production work остаётся blocked до B2. M7 выполняется отдельно как playable network validation поверх принятого A3.
