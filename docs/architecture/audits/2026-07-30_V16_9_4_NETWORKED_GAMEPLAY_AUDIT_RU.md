# Аудит сетевого gameplay перед B1

**Дата:** 30 июля 2026 года  
**Проверяемая база:** H1 + H2 + H3  
**Кандидат:** `v16.9.4-architecture-a2-networked-gameplay`

## Резюме

H1–H3 подтверждают основные сетевые invariants: authority-only mutation, stable player identity, ownership fencing, replay safety, two-peer isolation, replicated movement и deterministic contention. Network/runtime, world и main-scene regressions зелёные.

Архитектура может быть заморожена и B1 может начинаться как чистый B0 adapter stage. Однако multi-authority этапы N3–N6 пока заблокированы четырьмя P1-разрывами.

## Доказанные свойства

1. H1 graphical client читает replica и не получает authority/store/controller capability.
2. H1 Item Graph actions проходят command/result/delta boundary.
3. H2 reconnect сохраняет `player_entity_id` и увеличивает `ownership_epoch`.
4. H3 listener обслуживает два peer независимо.
5. H3 movement виден обоим clients через authoritative delta.
6. H3 contention создаёт один success и один `ITEM_ALREADY_CLAIMED`.
7. Permission probe запрещает игроку A менять inventory B.
8. Stale transport session и ownership epoch отклоняются.
9. Exact replay не повторяет mutation.
10. Authority/client final checksum совпадает.

## Найденные разрывы

### A2-D01 — несколько authority implementations

H1, H2 и H3 используют `PlayableListenHostAuthority`, `PlayerOwnershipRegistry` и `MultiplayerGameplayAuthority`. Семантика совместима по основным invariants, но общий production service contract ещё не реализован.

### A2-D02 — validators связаны с authority code

H2 replica store preloads registry, H3 replica/client preloads authority для validation/constants. Это не live authority access, но shared DTO validators должны быть вынесены до server mesh.

### A2-D03 — нет two-window graphical proof

H3 использует два headless Godot protocol processes. Movement/replication доказаны, graphical remote presentation и interpolation — нет. H3 contention использует reduced shared-item fixture, а не полный H1 Item Graph service.

### A2-D04 — dedicated crash/restart recovery не соединён с ownership

R3.1 и H1 persistence существуют, но H2/H3 доказывают reconnect только в пределах одной server lifetime.

## Решение

```text
A2 architecture target: FROZEN
B1 adapter work: ALLOWED WITH GATES
N3–N6 multi-authority work: BLOCKED
```

B1 не имеет права создавать новый gameplay path или связывать domain с NATS SDK. Closure A2-D01…D04 обязательно до N3.

## Машиночитаемый источник

`config/network/networked-gameplay-architecture.v1.json` является authoritative freeze manifest. `test_a2_networked_gameplay_architecture.gd` проверяет его согласованность с roadmap, ADR, docs и source evidence.
