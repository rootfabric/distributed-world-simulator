# Character track — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/ch7-8-skinned-garment`  
**Local role:** universal controllable-character presentation and equipment

## Зачем добавлен этот документ

Character track уже правильно отделяет controllable entity от конкретной модели, rig и first-person presentation. Глобальный P0 audit нужен здесь для того, чтобы будущая физика персонажа, экипировка и spatial integration не создали вторые authority/material/item foundations.

## Локальный план

Текущая линия сохраняется:

```text
CH4 animated avatar
CH5 full-body first person
CH6 controllable presentation
CH7 equipment domain/presentation
CH7.8 skinned garment bridge
```

Character track остаётся presentation/domain-adapter программой, а не владельцем canonical player identity.

## P0 dependencies

### Identity

```text
Player / Controllable Entity identity
    != avatar model
    != Skeleton3D
    != imported asset
    != garment mesh
```

Смена модели/rig не должна менять network/player/item identity.

### Spatial Domain Fabric

Character может иметь local body/ship/planet frame, но permanent position semantics принадлежат общему spatial/reference-frame foundation.

Character-specific node transform не становится world address.

### Materials and equipment

Equipment domain может ссылаться на Item identity. Visual material/skin/garment profile не является `MaterialDefinitionId` и не создаёт второй Item truth.

Если будущая броня/одежда получает физические material properties, они должны проецироваться из shared Material Ontology.

### NX7

Будущие режимы player/vehicle/body physics используют общую NX7 policy:

```text
SERVER_ONLY
OWNER_PREDICTED
OWNER_AUTHORITY_VALIDATED
PREDICTED_SPAWN
CLIENT_COSMETIC
```

Character track не заводит собственный owner registry.

### NX8

Character presenter является consumer interest/representation decisions. Visibility, skeleton LOD и garment quality не меняют canonical entity identity.

## Разрешённые локальные задачи

- новые rig adapters;
- avatar catalogs;
- full-body first-person improvements;
- equipment visual adapters;
- skinned garment pose bridge;
- animation retargeting;
- character presentation LOD research;
- different humanoid/non-humanoid presenters над общим controllable contract.

## Stop conditions

Character stage должен остановиться и вынести вопрос в global architecture, если потребуется:

- Player identity хранить внутри конкретной model scene;
- отдельный character authority registry;
- equipment visual state сделать источником Item truth;
- garment/render material использовать как canonical physical material;
- world position определять только Node3D transform без reference-frame contract;
- presentation LOD менять gameplay identity/state.

## Merge gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 или более новая синхронная revision
[PASS] global config byte-equivalent main
[PASS] network NX7-NX9 boundaries синхронизированы
[PASS] model/rig remain presentation adapters
[PASS] equipment identity remains compatible with Item domain
[PASS] CH focused/regression tests
```

Канонический общий план: `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
