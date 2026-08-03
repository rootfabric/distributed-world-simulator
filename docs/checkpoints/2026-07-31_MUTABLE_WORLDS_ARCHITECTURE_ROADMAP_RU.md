# Mutable Worlds architecture and roadmap checkpoint

Дата: `2026-07-31`
Base snapshot: `v16.10.6-architecture-a3-single-server-multiplayer`
Тип поставки: documentation-only planning patch
Runtime code changed: `false`

## Решение

Принята целевая парадигма `Dynamic Matter Fabric`:

```text
procedural volumetric base
+ deterministic geology and caves
+ sparse persistent matter mutations
+ independent render/storage/simulation/causal LOD
+ mass-conserving aggregate transactions
+ field ↔ fragment ↔ item ↔ construct transitions
```

`ADR-004-heightfield-plus-voxel.md` помечен superseded. Его заменяет `ADR-017-dynamic-matter-fabric.md`.

## Результат ревизии проекта

Подтверждено, что существующие foundations пригодны для новой системы:

- body-fixed reference frames;
- `CubeSphereGrid` для внешней surface identity;
- S0 hierarchical 3D simulation cells;
- A1 generic aggregates;
- M0 atomic multi-aggregate transactions;
- S1 authority/compute separation;
- multi-world runtime для отдельной лаборатории;
- async data-only terrain generation pattern.

Зафиксирована несовместимость текущего near Moon generator с ролью canonical geology: микрорельеф и локальные кратеры частично зависят от active surface window. Перед persistent matter integration требуется observer-independent canonical Moon sampler.

## Выбранная стратегия внедрения

1. Не переписывать текущую Луну немедленно.
2. Создать отдельный `asteroid_matter_lab`.
3. Зафиксировать астероид радиусом 1000 м и seed `2026073101`.
4. Пройти MW0–MW8 изолированно.
5. После laboratory gate выполнить MI0–MI4 gradual Moon integration.
6. После локальной семантики подключить MP0–MP4 network/distributed production track.

## Документы

- `docs/architecture/DYNAMIC_MATTER_FABRIC_RU.md`;
- `docs/architecture/adr/ADR-017-dynamic-matter-fabric.md`;
- `docs/plans/MUTABLE_WORLDS_ROADMAP_RU.md`.

## Следующий рекомендуемый checkpoint

```text
logical stage: MW0
branch: feature/mw0-matter-contracts
scope: pure matter contracts, material catalog, invariants and tests
production worlds changed: false
```


## Реализация первого этапа

MW0 implementation candidate вынесен в отдельный checkpoint:

- `docs/architecture/MW0_MATTER_CONTRACTS_RU.md`;
- `docs/checkpoints/2026-07-31_V17_0_0_SIMULATION_MW0_MATTER_CONTRACTS_RU.md`;
- `config/matter/mw0-matter-contracts.v1.json`.

Документационный roadmap остаётся целевым источником направления; статус MW0 до независимой проверки — `CANDIDATE`.
