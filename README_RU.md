# PlanetSimulator

Текущая принятая runtime-база: `v16.9.3-runtime-h3-dedicated-multiplayer`.

Текущий архитектурный кандидат: `v16.9.4-architecture-a2-networked-gameplay`.

A2 фиксирует доказанную H1–H3 client/server архитектуру: stable player identity, ownership/session fencing, authority-only movement и inventory mutations, replica-only client boundary, deterministic contention, reconnect/replay и peer isolation.

Решение A2: `FROZEN_WITH_GATES`.

```text
H1 accepted
H2 accepted
H3 accepted
A2 candidate
B1 next after A2 acceptance
```

B1 разрешён только как NATS Core adapter поверх B0 semantic ports. Он не может создавать новый gameplay path или переносить broker-specific state в domain. Multi-authority N3–N6 заблокированы до закрытия A2-D01…A2-D04.

Основные документы:

- `docs/checkpoints/2026-07-30_V16_9_4_ARCHITECTURE_A2_NETWORKED_GAMEPLAY_RU.md`;
- `docs/architecture/A2_NETWORKED_GAMEPLAY_ARCHITECTURE_RU.md`;
- `docs/architecture/adr/ADR-011-networked-gameplay-boundary.md`;
- `docs/architecture/audits/2026-07-30_V16_9_4_NETWORKED_GAMEPLAY_AUDIT_RU.md`;
- `config/network/networked-gameplay-architecture.v1.json`;
- `docs/plans/PLAYABLE_NETWORK_MILESTONES_RU.md`.
