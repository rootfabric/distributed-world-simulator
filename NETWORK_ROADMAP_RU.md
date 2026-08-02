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

## Network Experience NX0–NX9

С 1 августа 2026 года поверх принятой A3 single-server architecture открыт отдельный realtime-netcode roadmap:

```text
NX0 observability baseline
→ NX1 deterministic network condition simulator
→ NX2 traffic separation
→ NX3 fixed-tick authority
→ NX4 local prediction/reconciliation
→ NX5 remote interpolation
→ NX6 predicted item interactions
→ NX7 physics authority profiles
→ NX8 interest management
→ NX9 async persistence hardening
```

Текущий checkpoint candidate:

```text
v16.13.0-network-nx3-fixed-tick-authoritative-simulation
accepted base: v16.12.0-network-nx2-realtime-traffic-separation / fix2
base commit: f1abeca
branch: feature/nx3-fixed-tick-authoritative-simulation
runtime behavior changed: fixed 60-Hz authoritative movement simulation
server authority changed: no
fixed tick changed: yes
prediction changed: no
```

NX0 сохраняет matching fingerprint и bounded telemetry. NX1 добавляет детерминированные endpoint-local network conditions. NX2 разделяет шесть transport streams и подавляет movement amplification. NX3 выполняет movement только server fixed tick 60 Hz, независимо от packet arrival, client FPS и client `delta_seconds`; compact snapshots остаются на cadence 20 Hz. NX4 prediction остаётся следующим отдельным этапом.

Документы:

- `docs/network/NETWORK_EXPERIENCE_ROADMAP_NX0_NX9_RU.md`;
- `docs/network/NX3_FIXED_TICK_AUTHORITATIVE_SIMULATION_RU.md`;
- `docs/network/NX2_REALTIME_TRAFFIC_SEPARATION_RU.md`;
- `docs/network/NX1_DETERMINISTIC_NETWORK_CONDITION_SIMULATOR_RU.md`;
- `docs/network/NX0_OBSERVABILITY_BASELINE_RU.md`;
- `config/network/network-experience-roadmap.v1.json`;
- `config/network/nx3-fixed-tick-authoritative-simulation.v1.json`;
- `config/network/nx2-realtime-traffic-separation.v1.json`;
- `config/network/nx1-deterministic-network-condition-simulator.v1.json`;
- `config/network/network-condition-presets.v1.json`.

B1 остаётся допустимым server-to-server adapter после A3, но его реализация временно уступает продуктовому приоритету NX0–NX6. Existing B0/B1 contracts не изменяются.
