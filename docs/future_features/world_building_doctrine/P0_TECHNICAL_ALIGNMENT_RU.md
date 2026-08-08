# World Building Doctrine — P0 technical alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/world-building-doctrine`  
**Local role:** design doctrine for meaningful large worlds

## Зачем добавлен этот документ

Doctrine описывает, зачем игроку нужен большой мир: исследование должно оставлять последствия, превращаться в инфраструктуру, автоматизацию, общество и историю. После глобального архитектурного аудита эти design-принципы необходимо явно связать с техническими foundations, чтобы будущие gameplay-идеи не обходили canonical world model частными скриптовыми решениями.

## Design -> technical mapping

### WORLD -> HOME -> WORLD

```text
Discovery
 -> canonical WorldOperation
 -> persistent Item/Matter/Construction/Entity mutation
 -> new capability
 -> next world interaction
```

Награда не должна существовать только как transient UI flag, если по design она изменила мир.

### Освоенность территории

Состояния типа:

```text
UNKNOWN
OBSERVED
SURVEYED
EXPLORED
EXPLOITED
CONNECTED
SETTLED
INTEGRATED
```

не должны жёстко привязываться к render chunks или одному server shard. Их identity должна опираться на stable world/spatial semantics и переживать authority rebalance.

### Infrastructure

```text
base / road / station / mine / factory
```

выражаются через существующие домены Construction, Item, Matter и future logistics, а не через отдельный doctrine-owned world state.

### Capability progression

Capability может зависеть от:

- Item/equipment;
- construction/machine state;
- material/technology knowledge;
- environmental access;
- organization/permissions.

Но presentation и UI не становятся canonical source capability.

## P0 constraints for design work

### Spatial

Большой мир проектируется поверх `Spatial Domain Fabric`. Design region/biome/territory не обязан совпадать с SurfaceCell, MatterRegion, AuthorityRegion или InterestRegion.

### Material

Ресурсы, geology, производство и recycling должны опираться на общую Material Ontology, чтобы exploration -> mining -> processing -> construction образовывали одну причинную цепочку.

### Transactions

Gameplay loops типа:

```text
mine ore
build module
salvage wreck
trade physical resource
```

не должны предполагать, что несколько независимых RPC автоматически образуют одно надёжное действие. Для этого используется общий WorldOperation/WorldTransaction foundation.

### Network

Latency/prediction/interest — presentation and delivery concerns. Они не должны менять смысл владения, освоенности, resource conservation или результата строительства.

## Связь с будущими P1 foundations

Doctrine особенно зависит от следующих будущих систем:

```text
Time Fabric
 -> развитие мира без симуляции каждого frame

Hierarchical Navigation / AI
 -> агенты реально используют большой мир

Promotion / Dormancy / Demotion
 -> мир помнит последствия без миллиарда live entities

World Work / Budget Fabric
 -> большая симуляция остаётся вычислительно ограниченной
```

Текущие design-документы не должны вводить предположения, которые блокируют эти foundations.

## Stop conditions

Design proposal требует architecture review, если он предполагает:

- permanent identity через chunk/LOD;
- отдельную material semantics только ради одной механики;
- player progression, существующую только в UI при заявленном world-state effect;
- script chain без durable cross-domain result для значимой world mutation;
- один server как постоянного владельца территории;
- необходимость материализовать все procedural objects как canonical entities заранее.

## Локальный merge gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 или более новая синхронная revision
[PASS] global config byte-equivalent main
[PASS] network NX7-NX9 boundaries синхронизированы
[PASS] doctrine сохраняет progress-as-world-state principle
[PASS] design regions не подменяют technical spatial identities
[PASS] future gameplay loops совместимы с WorldOperation model
```

Канонический общий план: `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
