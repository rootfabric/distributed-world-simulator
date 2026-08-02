# CH0 — Universal Character Presentation Roadmap Branch

**Дата:** 3 августа 2026 года  
**Ветка:** `feature/ch0-universal-character-presentation-roadmap`  
**База:** `main @ 69bd7fc7fde2bc0824b0d608451ecd310397b8d2`  
**Первый roadmap commit:** `391ddedb5e0891f0458ff6b5a28bff7abb5cd45c`  
**Статус:** `DOCUMENTATION CHECKPOINT`

## Назначение

Зафиксирована отдельная линия подготовки универсального presentation-слоя персонажей. Ветка не внедряет модель в production runtime и не меняет authoritative simulation.

Основной документ:

```text
docs/plans/UNIVERSAL_CHARACTER_PRESENTATION_ROADMAP_RU.md
```

## Изученный интеграционный план

```text
branch: agent/three-domain-integration-merge-plan
head:   9742f8acf342dbc9712b8f2371e8f009c3d2cfc1
file:   docs/plans/THREE_DOMAIN_INTEGRATION_MERGE_PLAN_RU.md
```

Зафиксированные merge targets:

```text
Construction / Items: C24 ACCEPTED
Network:              NX6 ACCEPTED
Matter / Surface:     MW10 + RL3 ACCEPTED
integration branch:   integration/c24-nx6-mw10-rl3
```

## Состояние активных линий на момент создания CH0

```text
Construction:
  branch: feature/c24-gpu-ready-proxy-mesh-backend
  head:   8623d0e5b4b6455fb4a75f2cc04c6cb5d3c38cb8

Network:
  branch: feature/nx3-fixed-tick-authoritative-simulation
  head:   9a6081402453c3586efc6c2dce0e64c6097f2505

Matter / Representation:
  branch: feature/rl1-matter-summary-pyramid
  head:   f0a7328d935d752858a77b0364260ee40b63b073
```

Эти SHA являются наблюдаемыми точками, а не базой character branch.

## Решение по изоляции

Character branch создаётся от `main`, а не от одной из трёх активных domain branches.

Разрешённая независимая разработка:

```text
CH0 roadmap and audit
CH1 contracts and registry
CH2 humanoid import lab
CH3 isolated presentation host
```

Независимая остановка:

```text
CH3 ACCEPTED
```

Запрещено до синхронизации:

```text
CH4 production local/remote player integration
CH5 networked character identity/action state
CH6 production equipment and interaction poses
CH7 production relevance/LOD hardening
```

## Причина остановки на CH3

NX3–NX6 и трёхдоменная интеграция изменяют или будут изменять:

```text
scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd
scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd
scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd
scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd
scripts/app/simulator_app.gd
scripts/items/presentation/item_gameplay_controller.gd
```

Независимое production wiring персонажа в этих файлах создаст конфликт с NX5 remote interpolation, NX6 predicted item interactions и INT1 runtime decomposition.

## Обязательная точка синхронизации

```text
C24 + NX6 + MW10 + RL3 frozen
→ INT0 Canonical Integration Base ACCEPTED
→ INT1 Runtime Decomposition ACCEPTED
→ перенос CH0–CH3 foundation
→ CH4 integrated player presentation
```

CH5 выполняется после `INT2 Unified Traffic Classes`.

Character LOD и production relevance выполняются после `INT6 Unified Interest and Streaming`.

## Политика ветки

- не merge-ить C/NX/MW-RL branches внутрь character branch по отдельности;
- до CH3 использовать additive paths `scripts/characters/**`, `tests/characters/**`, `scenes/labs/character/**`, `config/characters/**`;
- не переписывать историю;
- каждый этап фиксировать отдельным checkpoint;
- после CH3 заморозить production wiring до INT1;
- перенос на integration base выполнять контролируемыми commits, не стратегией `ours/theirs`;
- dedicated server не должен загружать character assets;
- model, skeleton и animation state не являются canonical world state.

## Следующий этап

```text
CH1 — Character Presentation Contracts and Registry
```

CH1 должен быть headless-safe и не изменять M3 runtime.
