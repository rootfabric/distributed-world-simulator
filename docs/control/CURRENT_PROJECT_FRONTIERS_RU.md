# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Canonical main at this refresh:** `e14f8b6e5b07709d18273cc7886fe660bc353ebf`  
**Refresh date:** 2026-08-29  
**Machine product policy:** `config/control/harness/v0-product-train-policy.v1.json`

> Machine truth remains in `config/control/**`. This file is a human-readable routing snapshot. Branch implementation progress is not checkpoint acceptance until the required control/review/merge lifecycle completes.

## Главный продуктовый приоритет

Главная product line — V0/P.

Фактическая последовательность сейчас:

```text
P4 real-resource Construction         ACCEPTED
→ P5 equipment / tools                ACCEPTED
→ P6 persistent shared outpost        ACCEPTED
→ Edge Gateway Foundation             ACCEPTED
→ SM1 seamless product integration    ACTIVE / NOT ACCEPTED
→ P7 bounded terrain mutation         NEXT AFTER SM1
→ V0 PLAYABLE SEAMLESS PLANET         NORTH STAR PRODUCT MILESTONE
→ P8 first mobile construct / ship
```

Глобальная roadmap:

`docs/plans/V0_PLAYABLE_SEAMLESS_PLANET_ROADMAP_RU.md`

Progress baseline для будущего сравнения:

`docs/checkpoints/2026-08-28_V0_PLAYABLE_SEAMLESS_PLANET_PROGRESS_R2_RU.md`

## Принятый persistent-playable фундамент

### P4 — Real Resource Construction

**ACCEPTED**

Accepted runtime:

`2a6721cdf02fa1134c59d1ab98bb7b597c66821d`

P4 уже даёт canonical mining/resource -> Item Graph -> resource-backed Construction loop. Не планировать mining/Construction как новые системы для ближайшего большого checkpoint.

### P5 — Equipment / Tools

**ACCEPTED**

Accepted runtime:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

Equipment/tools уже server-authoritative и являются частью playable loop.

### P6 — Persistent Shared Outpost

**ACCEPTED**

Accepted runtime:

`7a77c048caa680871d4895c09eca89e84136b154`

P6 закрепляет shared two-client outpost, reconnect, persistence, server restart reconstruction, repeated E2E и soak.

### Edge Gateway Foundation

**ACCEPTED**

Gateway foundation уже consumed by P6/SM1. Не открывать новый Gateway owner для текущего product critical path.

## Current runtime frontier — SM1

Canonical production branch:

`feature/v0-sm1-seamless-product-integration`

Observed validated implementation head на момент refresh:

`b270fb806038333c97fa1ed49655961adddd6a21`

PR #242 остаётся Draft. Следовательно:

```text
IMPLEMENTED / EXACT-HEAD EXECUTABLE EVIDENCE
!=
SM1 CHECKPOINT ACCEPTED
```

Runtime implementation дошёл до SM1.7.12 и feature scope завершён:

- owner-port map;
- one-writer transfer;
- stable Player Carrying Domain;
- Gateway route pivot;
- world-state continuity;
- five-process graphical A<->B;
- fault/replay/stale-source matrix;
- concurrent crossings;
- reconnect after handoff;
- Gateway restart;
- Authority recovery;
- canonical Item Graph / Construction / outpost mutations across handoff;
- repeated A<->B crossings under deterministic BAD_MOBILE/LAG_SPIKE impairment.

Exact-head evidence на `b270fb8...` включает:

```text
SM1.7.12         70 x 10 = 700 PASS
SM1 L0                  339/339 PASS
SM1.6 graphical          58/58 PASS
SM1.7.1-7.6             157/157 PASS
SM1.7.7                  79/79 PASS
SM1.7.8                  71/71 PASS
SM1.7.9                  81/81 PASS
SM1.7.10                 89/89 PASS
SM1.7.11                145/145 PASS
Project Control #1439             SUCCESS
```

**B2 full world/core regression = CLOSED.**

Composite regression-repair candidate:

`6fdfc047f54e727e6b398370e576c746c7949441`

tree `b9b1202d959b3da4a0c73840091c7bf56070429e`, Draft PR #282 over exact SM1.7.12 `b270fb8...`.

Exact Windows double-Godot evidence: **307/307 steps PASS**, `304/304` standalone tests, `main_scene_cli_all` PASS, `summary.passed=true`.

Текущая работа — **B2.5 manual seamless smoke demo**.

Closure path:

```text
B2 full world/core regression             CLOSED
→ manual seamless smoke demo              CURRENT (non-acceptance)
→ post-build critique
→ Evidence Map
→ fresh Reviewer
→ fresh Verifier
→ checkpoint proposal
→ human RUNTIME_FEATURE_MERGE
→ SM1 ACCEPTED
```

## Pre-P7 manual seamless smoke demo

Технический smoke/demo бесшовности можно собрать уже на current SM1 candidate, не дожидаясь P7:

```text
Authority A
+ Authority B
+ Gateway
+ graphical client
→ client connects only to Gateway
→ manual A -> B -> A crossing
→ no reconnect / respawn / loading
```

Текущий graphical SM1 client script-driven, поэтому для tester-facing demo нужен отдельный тонкий manual-input/presentation wrapper. Это packaging/presentation work, а не новый authority protocol.

Рекомендуемый момент достигнут: **B2 закрыт; manual seamless smoke demo = CURRENT**, до critique/review closure. Demo не означает SM1 acceptance.

## Next product runtime frontier — P7

После SM1 acceptance следующий основной gameplay block:

**V0_P7_BOUNDED_TERRAIN_MUTATION**

P7 должен добавить authoritative mutable planetary surface без второй terrain/Matter truth.

Минимальная вертикаль:

```text
equipped tool
→ authoritative dig command
→ canonical terrain/material mutation
→ material/resource yield
→ canonical Item Graph
→ two-client replication
→ reconnect reconstruction
→ server restart reconstruction
→ seamless-boundary mutation continuity
```

P7 не должен переизобретать уже принятые P4/P5 mining, inventory, tool или Construction owners.

## North Star — V0 PLAYABLE SEAMLESS PLANET

После P7 требуется отдельный product-level graphical acceptance.

Два graphical clients должны на одном bounded planetary patch:

- видеть один persistent world;
- ходить и взаимодействовать;
- добывать ресурс;
- копать/изменять поверхность;
- получать canonical material;
- строить из canonical resources;
- пересекать A/B boundary без respawn/reconnect/loading;
- продолжать dig/build после handoff;
- переживать reconnect;
- переживать server restart;
- сходиться к одной canonical truth.

Current navigation estimate после B2 closure:

**~82% функциональной готовности до этого milestone.**

Это product navigation metric, не Harness acceptance state.

## ECO

ECO продолжает параллельный research frontier и **не блокирует V0/P по умолчанию**.

Наблюдаемая live-spatial линия дошла до LS3.3 Dispersal / Recruitment staging/evidence после LS3.0-3.2.

План:

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

Research становится product blocker только через явную main-owned dependency/ownership intersection.

## Critical-path discipline

До V0 PLAYABLE SEAMLESS PLANET:

```text
SM1 closure
→ P7 terrain mutation
→ North Star graphical acceptance
```

Не добавлять на critical path без доказанного blocker:

- P8 mobile construct;
- arbitrary-N authority balancing;
- dynamic shard split/merge;
- новый transport foundation;
- новый Gateway;
- full planet HLOD/MRPF completion;
- ECO product promotion.

## Fail-closed boundaries

STOP_AND_REPLAN если текущий путь требует:

- second Item Graph owner;
- second Construction truth;
- second persistence owner;
- Gateway gameplay/ownership authority;
- client-private terrain truth;
- direct client connection to simulation authorities вместо stable Gateway endpoint;
- successor runtime before predecessor acceptance;
- research branch wholesale merge как product base;
- скрытый scope expansion SM1 до dynamic global sharding.

## Следующая точка progress review

Сравнить с snapshot 2026-08-28 и ответить:

1. принят ли SM1;
2. какой accepted SM1 head;
3. активирован ли P7;
4. работает ли authoritative terrain mutation;
5. материализуется ли dig result в Item Graph;
6. переживает ли terrain reconnect/restart;
7. проходит ли mutation через A/B seam;
8. достигнут ли V0 PLAYABLE SEAMLESS PLANET.
