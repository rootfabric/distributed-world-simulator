# Checkpoint v16.5.0 — Network N1.1 ENet handshake и initial snapshot

**Дата:** 28 июля 2026 года

**Статус:** candidate для независимой проверки

**База:** `v16.4.2-network-transport-boundary`

**Ветка:** `feature/n1-enet-snapshot`

**Build ID:** `n1-enet-handshake-initial-snapshot`

## Цель

Доказать реальный сетевой обмен между двумя отдельными headless Godot-процессами без изменения доменных DTO:

```text
simulation-server
        ↕ ENet
bot-client
```

Server и client выполняют handshake, согласуют capabilities и версии контрактов, передают initial `EntitySnapshotEnvelope`, подтверждают checksum и корректно завершаются.

## Реализация

Добавлены:

- `NetworkWireFrame` — канонический JSON wire envelope с payload SHA-256;
- `NetworkHandshakeEnvelope`;
- `NetworkHandshakeResultEnvelope`;
- `SnapshotAckEnvelope`;
- `NetworkHandshakeService`;
- `ENetTransportPort` поверх общего N1.0 boundary;
- server/client snapshot sessions;
- отдельные SceneTree entrypoints для server и bot-client;
- process support с фиксированным тестовым snapshot;
- контрактный и настоящий двухпроцессный тест;
- отдельный PowerShell runner `RUN_N1_ENET_SNAPSHOT_TESTS.ps1`.

## Границы

В N1.1 не входят:

- удалённая item mutation;
- reconnect и replay;
- второй authoritative server;
- World Directory;
- authority handoff;
- ghosts и interest management.

Следующий этап: N1.2, удалённая `item.move_to_container` через тот же ENet port и N0 command DTO.

## Безопасность контракта

Отклоняются:

- дополнительные/отсутствующие поля DTO;
- unsafe JSON integers и Godot runtime objects;
- malformed, invalid UTF-8 и non-canonical JSON packets;
- неизвестные message types;
- повреждённые payload/checksum;
- protocol/role mismatch;
- отсутствующие capabilities и несовместимые contract versions;
- несогласованные snapshot authority owner/epoch/tick;
- неожиданные negotiated capabilities;
- snapshot acknowledgement другой session/entity/checksum;
- ранний disconnect и process timeout.

## Acceptance

```text
editor import/parse                      PASS
N1.1 contract tests                      PASS
real server/client process test          PASS
server/client snapshot checksum equal    PASS
N0/N1 network profile                    PASS
full Godot regression                    PASS
main scene CLI                           PASS
simulation-server lifecycle              PASS
git diff --check                         PASS
```

Фактические числа и SHA-256 артефактов фиксируются в validation report поставки.
