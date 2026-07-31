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
