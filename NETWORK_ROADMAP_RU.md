# PlanetSimulator — current network and multiplayer roadmap

Принятая architecture-база: `v16.9.4-architecture-a2-networked-gameplay`.
Принятый roadmap checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.
Принятый runtime checkpoint: `v16.10.5-persistence-m6-dedicated-recovery` (`ACCEPTED`, delivery `fix1`).
Текущий architecture-кандидат: `v16.10.6-architecture-a3-single-server-multiplayer`.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 → A2 → M1 → M2 → M3 → M4 → M5 → M6 accepted
A3 candidate implemented
B1/B2 deferred until A3 acceptance
N3–N6 blocked until A3 and B2
```

## A3 single-server multiplayer architecture freeze

A3 не создаёт второй gameplay runtime. Он машинно фиксирует и независимо проверяет доказанную цепочку M1–M6:

- единственный production composition root — `NetworkedGameplayService`;
- LOOPBACK и ENet являются authority adapters над одинаковыми командами и canonical state;
- graphical clients содержат только transport, command gateway, replica store и presentation;
- movement, presentation, inventory/hotbar, Item Graph, contention, reconnect, replay и recovery используют один authoritative path;
- M6 закрывает `A2-D04`; transport sessions и UI overlays остаются transient;
- B1 разрешён после принятия A3 только как server-to-server adapter через существующие B0 ports;
- несколько authoritative gameplay servers остаются запрещены до B2 и последующих N3–N6.

Главный acceptance-инвариант:

> Одинаковая последовательность команд через LOOPBACK и ENet приводит к одному canonical checksum, а crash/restart и exact replay не создают topology-specific fork или повторную мутацию.

Authoritative sources:

- `config/network/single-server-multiplayer-architecture.v1.json`;
- `docs/architecture/A3_SINGLE_SERVER_MULTIPLAYER_ARCHITECTURE_RU.md`;
- `docs/architecture/adr/ADR-016-single-server-multiplayer-architecture-freeze.md`;
- `docs/architecture/audits/2026-07-31_V16_10_6_SINGLE_SERVER_MULTIPLAYER_AUDIT_RU.md`;
- `docs/checkpoints/2026-07-31_V16_10_6_ARCHITECTURE_A3_SINGLE_SERVER_MULTIPLAYER_RU.md`;
- `config/network/dedicated-persistence-recovery.v1.json`;
- `config/network/networked-gameplay-architecture.v1.json`;
- `config/network/single-server-multiplayer-roadmap.v1.json`;
- `config/network/network-roadmap.v1.json`.

## Parallel matter networking track — MW7 accepted, MW8 candidate

MW6 `v17.6.0-simulation-mw6-matter-network-replication` delivery `fix2` принят: один authoritative matter writer, exact binary64 wire DTO, persistent-only global stream, reconnect replay/snapshot fallback.

MW7 `v17.7.0-simulation-mw7-matter-interest-replication` не меняет A3 production gameplay topology. Он добавляет projection-layer над тем же MW6 authority: interest peers используют существующий command gateway, но получают через `ReplicationEnvelope(kind=INTEREST)` только persistent bricks своей cell-region. Cross-server authority, NATS gameplay и production Moon integration остаются за пределами этапа.


## MW8 regional authority handoff candidate

MW8 остаётся изолированным matter-track и не отменяет single-server A3 gameplay freeze. Для одной зарегистрированной cell-region вводится checksum-protected lease directory и двухфазный handoff между двумя `MatterAuthoritativeServer`: source freeze, exact state package, target prepare с компенсацией, directory commit owner/epoch. MW7 interest client после commit подключается к target и получает filtered regional snapshot. Операция, затрагивающая несколько authority-regions, намеренно запрещена до отдельного distributed transaction этапа. Пакет handoff привязан к body/grid/lease, а focused lifecycle явно отписывает MW7 projection observers.
