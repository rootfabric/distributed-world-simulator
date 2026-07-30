# PlanetSimulator — текущая distributed runtime roadmap

Принятая runtime-база: `v16.9.3-runtime-h3-dedicated-multiplayer`.
Текущий архитектурный кандидат: `v16.9.4-architecture-a2-networked-gameplay`.

```text
A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1 accepted
H1 → H2 → H3 accepted
A2 candidate: FROZEN_WITH_GATES
B1 next after independent A2 acceptance
```

A2 разрешает B1 только как adapter-only этап через B0 semantic ports. NATS не может менять gameplay command, identity, ownership, replay или authority semantics.

Перед N3 должны быть закрыты:

- A2-D01 — единый production `NetworkedGameplayService` для H1/H2/H3;
- A2-D02 — shared DTO validators вне authority implementations;
- A2-D03 — два graphical clients и полный Item Graph over dedicated transport;
- A2-D04 — dedicated crash/restart recovery player/gameplay state.

Дальнейший порядок:

```text
A2 → B1 → B2 → P0 → D1 → N3 → N4 → N5 → N6
```

Источник архитектурного freeze: `config/network/networked-gameplay-architecture.v1.json`.
