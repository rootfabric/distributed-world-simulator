# V0 PLAYABLE SEAMLESS PLANET — глобальная продуктовая дорожная карта

**Revision:** R3 / 2026-08-29  
**Primary purpose:** сфокусировать product critical path на первом полноценном playable seamless world milestone.

> Эта roadmap — human product-routing document. Canonical checkpoint eligibility, ownership и acceptance по-прежнему определяются `config/control/harness/v0-product-train-policy.v1.json` и остальным main-owned control plane.

## North Star checkpoint

# V0 PLAYABLE SEAMLESS PLANET

Это первый рубеж, после которого проект должен ощущаться не как набор инфраструктурных доказательств, а как ранняя persistent multiplayer game.

Acceptance scenario:

```text
1. Запустить dedicated server / Gateway / Authority A / Authority B.
2. Подключить два graphical client.
3. Оба игрока видят общий canonical world.
4. Игрок экипирует tool.
5. Добывает canonical resource.
6. Копает/изменяет bounded terrain.
7. Получает материал в canonical Item Graph.
8. Строит из canonical resources.
9. Второй клиент видит тот же результат.
10. Игрок пересекает A/B authority boundary без respawn/reconnect/loading.
11. Продолжает копать и строить после handoff.
12. Disconnect/reconnect восстанавливает тот же player/world state.
13. Server restart восстанавливает terrain + inventory + equipment + Construction.
14. Duplicate/stale operations не создают вторую canonical truth.
```

## Фаза A — persistent multiplayer foundation

**Статус: DONE / ACCEPTED foundation**

- P4 real-resource Construction — ACCEPTED;
- P5 equipment/tools — ACCEPTED;
- P6 persistent shared outpost — ACCEPTED;
- Edge Gateway Foundation — ACCEPTED;
- two-client persistence/reconnect/restart foundation существует.

Не открывать альтернативные Item Graph, Construction, persistence или Gateway owners.

## Фаза B — SM1 production seamless

**Статус: ACTIVE / feature-complete, B2 closed; manual seamless smoke current**

Уже реализовано до SM1.7.12:

- one-writer transfer;
- stable logical player/entity identity;
- monotonic authority epoch;
- Gateway route preservation;
- graphical A<->B;
- fault/replay cases;
- concurrent crossings;
- reconnect;
- Gateway restart;
- Authority recovery;
- canonical gameplay mutation continuity;
- repeated A<->B crossings under BAD_MOBILE/LAG_SPIKE network impairment.

Текущий exact implementation candidate:

`b270fb806038333c97fa1ed49655961adddd6a21`

SM1.7.12 закрыт: **700/700 PASS**, regression belt PASS, Project Control #1439 SUCCESS.

B2 composite regression-repair candidate:

`6fdfc047f54e727e6b398370e576c746c7949441`

tree `b9b1202d959b3da4a0c73840091c7bf56070429e`, Draft PR #282 over exact `b270fb8...`.

Exact Windows double-Godot B2: **307/307 steps PASS**, `304/304` standalone tests, `main_scene_cli_all` PASS, `summary.passed=true`. Durable closure is linked from PR #242.

Осталось:

```text
B1. SM1.7.12 impaired-network repeated crossings    DONE
B2. full world/core regression                       CLOSED
B2.5 manual seamless smoke demo                      CURRENT
B3. post-build critique
B4. Evidence Map
B5. fresh exact-head Reviewer
B6. fresh Verifier
B7. checkpoint proposal
B8. human RUNTIME_FEATURE_MERGE
```

### Pre-P7 manual seamless smoke demo

B2 закрыт. Текущая product-facing точка — собрать отдельный non-acceptance tester demo без terrain mutation:

```text
Authority A + Authority B + Gateway
→ graphical client connects only to Gateway
→ manual movement across visible A/B boundary
→ A -> B without loading/reconnect/respawn
→ B -> A
→ repeated crossings
```

SM1 protocol для этого уже реализован. Нужен только тонкий manual-input/presentation wrapper поверх существующих process workers; текущий graphical client остаётся script-driven. P7/terraforming для такого demo не требуется.

Exit condition: **SM1 ACCEPTED**.

## Фаза C — P7 bounded terrain mutation

**Статус: NEXT PRODUCT RUNTIME BLOCK**

Цель P7 — не "сделать новый terrain engine", а добавить authoritative mutable surface к уже существующему persistent/seam-aware product.

Минимальные slices:

### P7.1 Canonical bounded mutation

- определить/переиспользовать canonical Matter/terrain owner;
- bounded dig/remove operation;
- deterministic OperationId;
- server-only authoritative mutation;
- no client-private terrain truth;
- stable material/voxel/patch identity.

### P7.2 Dig -> resource

```text
equipped tool
→ authoritative dig command
→ terrain/material debit
→ canonical resource yield
→ Item Graph
→ replicated inventory/world result
```

Добыча ресурса не должна дублировать существующий P4/P5 resource path.

### P7.3 Replication + durability

- two-client convergence;
- deterministic terrain delta/fingerprint;
- disconnect/reconnect reconstruction;
- server restart reconstruction;
- stale/duplicate command fencing;
- bounded compaction/snapshot strategy.

### P7.4 Seam-aware terrain mutation

Проверить:

```text
A active: dig/build
→ A->B transfer gap: writes fenced
→ B active: dig/build
→ B->A
→ canonical terrain + Item Graph + Construction converge
```

Gateway не решает terrain ownership.

### P7.5 Graphical product acceptance

Два реальных клиента на bounded planetary patch:

- walk;
- mine;
- dig;
- build;
- cross seam;
- dig/build again;
- reconnect;
- restart;
- same world.

Exit condition: **P7 ACCEPTED + V0 PLAYABLE SEAMLESS PLANET graphical acceptance**.

## Фаза D — big checkpoint closure

После P7 выполнить отдельный product-level acceptance, а не считать P7 unit acceptance автоматически равным North Star.

Обязательные доказательства:

- 2 graphical clients;
- real dedicated processes;
- stable Gateway endpoint;
- A<->B crossing;
- terrain mutation;
- mining/material yield;
- resource-backed Construction;
- reconnect;
- server restart;
- repeated clean runs;
- bounded soak;
- zero duplicate canonical truth.

После этого фиксируется:

**V0 PLAYABLE SEAMLESS PLANET — ACHIEVED**

## Фаза E — P8 first mobile construct

Только после North Star:

```text
Construction
+ Item Graph/resources
+ persistence
+ reference frames
+ terrain/world relation
+ seam-aware authority
→ bounded mobile construct / rover / ship
```

P8 не блокирует первый seamless planet checkpoint.

## Фаза F — seamless scale-out

После доказанного static A<->B product:

- arbitrary N authorities;
- load-aware placement;
- dynamic ownership assignment;
- shard/region split;
- merge;
- failure redistribution;
- moving Interaction Islands;
- stronger WAN/fault models.

Не расширять SM1 до этих задач до его acceptance.

## Фаза G — planetary presentation scale

После working gameplay:

- hierarchical projection / MRPF;
- planet -> region -> local patch representation;
- surface HLOD;
- distant constructs/outposts;
- large-scale visibility;
- projection continuity independent of simulation ownership.

Это presentation scale, не prerequisite для bounded playable surface.

## Фаза H — living planet / ECO integration

ECO продолжает research line параллельно.

Текущая live-spatial последовательность:

```text
LS3.0 Real Planet Patch
→ LS3.1 Environment Generator
→ LS3.2 Spatial Cohort Lattice
→ LS3.3 Dispersal / Recruitment
→ LS3.4 Competition
→ LS3.5 Emergent Biomes
→ LS3.6 Rule Workbench
→ LS3.FINAL
```

ECO подключается к продукту только через явный integration/ownership contract. До этого research status alone не является V0 blocker.

## Critical-path rule

До достижения V0 PLAYABLE SEAMLESS PLANET приоритет:

```text
SM1 closure
    ↓
P7 terrain mutation
    ↓
North Star graphical acceptance
```

Не начинать на critical path:

- P8;
- новый Gateway;
- новый network transport;
- second Item Graph/Construction/persistence owner;
- global dynamic shards;
- full planet HLOD;
- ECO product promotion.

Исключение — доказанный blocker текущего SM1/P7 Work Order.

## Progress metric

Baseline 2026-08-28:

**~80% до V0 PLAYABLE SEAMLESS PLANET по функциональной готовности.**

Current navigation after B2 closure (2026-08-29): **~82%**, не Harness acceptance.

Historical comparison snapshot:

`docs/checkpoints/2026-08-28_V0_PLAYABLE_SEAMLESS_PLANET_PROGRESS_R2_RU.md`
