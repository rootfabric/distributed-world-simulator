# V0 / P — правила развития продуктовой ветки

**Owner:** `main`  
**Machine policy:** `config/control/harness/v0-product-train-policy.v1.json`  
**Human roadmap:** `docs/plans/V0_PLAYABLE_SEAMLESS_PLANET_ROADMAP_RU.md`

> Этот документ объясняет product routing. Machine eligibility и acceptance не выводятся из текста этой страницы.

## Что такое P

P — одна последовательная playable product line. Каждый следующий этап обязан продолжать уже принятую canonical композицию.

Актуальная последовательность:

```text
P4 real-resource Construction         ACCEPTED
→ P5 equipment / tools                ACCEPTED
→ P6 persistent shared outpost        ACCEPTED
→ POST-P6 seamless decision           ACTIVATE_SM1
→ SM1 seamless product integration    ACTIVE / NOT ACCEPTED
→ P7 bounded terrain mutation
→ V0 PLAYABLE SEAMLESS PLANET         product milestone
→ P8 first mobile construct / ship
```

Главное правило не меняется:

```text
reviewed/verified implementation
!=
accepted predecessor checkpoint
```

Следующий runtime checkpoint не стартует до formal predecessor acceptance и main-owned successor activation.

## Текущее положение — SM1

P4, P5 и P6 уже приняты. Edge Gateway Foundation также принят.

Текущий runtime owner line:

`feature/v0-sm1-seamless-product-integration`

Observed validated head на refresh 2026-08-28:

`716ed913f9835593a31d142a556d78833c7088b1`

PR #242 остаётся Draft; SM1 ещё не accepted/merged.

SM1 implementation уже включает:

- one-writer authority handoff;
- stable player/entity identity;
- Gateway-preserving routing;
- A<->B graphical process scenario;
- stale/replay/failure fencing;
- concurrent crossings;
- reconnect;
- Gateway restart;
- Authority recovery;
- Item Graph / Construction / outpost mutation continuity.

Следующий runtime slice:

**SM1.7.12 repeated crossings under impaired network**

После него нельзя сразу открывать P7. Сначала:

```text
full world/core regression
→ post-build critique
→ Evidence Map
→ fresh Reviewer
→ fresh Verifier
→ checkpoint proposal
→ human RUNTIME_FEATURE_MERGE
→ SM1 ACCEPTED
```

## Как открывать следующий checkpoint

Для P7 и P8 применяется прежняя схема:

```text
PREDECESSOR CHECKPOINT ACCEPTED
        ↓
fetch current main + referenced branches
        ↓
standard + directional Project Control NON_RED
        ↓
main declares exact accepted predecessor product base
        ↓
fresh bounded successor branch
        ↓
new Project Epoch + Work Order
        ↓
risk classification + Design Brief
        ↓
mutation lease rotation
        ↓
Director dispatch
        ↓
bounded implementation
        ↓
freeze exact runtime head
        ↓
fresh Reviewer + Verifier
        ↓
append-only closure
        ↓
checkpoint proposal / human gate
```

Запрещено:

- начинать successor от bare main, если теряется accepted product composition;
- wholesale merge donor/research branch как product base;
- создавать второго owner для Item Graph / Construction / persistence / terrain;
- считать Draft PR acceptance.

## Уже принятый foundation нельзя переизобретать

### P4

Mining/resource-backed Construction уже принят.

Не строить новый parallel loop:

```text
new resource truth
→ new inventory truth
→ new construction truth
```

Новый capability должен потреблять existing canonical owners.

### P5

Equipment/tools уже принят.

P7 dig action должен использовать existing equipment/tool identity, а не private terrain tool state.

### P6

Persistent Shared Outpost уже принят.

Terrain persistence должна композиционно добавиться к существующим reconnect/restart semantics, а не создать отдельный V0 durability stack.

### Edge Gateway

Gateway foundation уже принят и остаётся non-authoritative.

Gateway не должен решать terrain ownership, Construction truth или Item Graph truth.

## P7 — bounded terrain mutation

P7 — следующий крупный runtime block после SM1 acceptance.

Цель:

**authoritative mutable planetary surface inside the existing persistent seamless product.**

Минимальная вертикаль:

```text
tool equipped
→ dig command
→ server authority validates
→ bounded terrain/material mutation
→ material yield
→ canonical Item Graph
→ client A/B convergence
→ reconnect
→ server restart
→ same terrain state
```

### Ownership rules

P7 обязан:

- переиспользовать canonical Matter/terrain authority или явно создать ровно один main-approved canonical owner;
- не создавать client-private terrain truth;
- не создавать parallel resource economy;
- использовать deterministic OperationId;
- fail closed на stale/duplicate operation;
- иметь deterministic terrain fingerprint/delta representation.

### Seam requirement

После принятого SM1 P7 обязан доказать:

```text
A active: dig/build
→ transfer starts
→ A/B writes during unsafe gap are fenced
→ B active: dig/build
→ B->A
→ terrain + Item Graph + Construction remain canonical
```

Если P7 требует менять фундамент authority transfer, работа fail-closed возвращается в соответствующий network/authority owner, а не чинится private workaround'ом.

## V0 PLAYABLE SEAMLESS PLANET

Это **product milestone overlay**, а не новый machine checkpoint в текущей policy revision.

После P7 acceptance нужен отдельный graphical E2E gate.

Два клиента должны доказать:

1. shared persistent world;
2. equipment/tool;
3. mining;
4. terrain digging;
5. material in Item Graph;
6. resource-backed Construction;
7. seamless A<->B crossing;
8. continued dig/build after crossing;
9. reconnect;
10. server restart;
11. repeated clean runs / bounded soak;
12. zero duplicate canonical truth.

Только после этого milestone считается достигнутым.

Progress baseline:

`docs/checkpoints/2026-08-28_V0_PLAYABLE_SEAMLESS_PLANET_PROGRESS_R1_RU.md`

## P8 — first mobile construct / ship

P8 идёт **после** North Star milestone.

Он должен собрать:

```text
Construction
+ canonical items/resources
+ persistence
+ reference frames
+ terrain/world relation
+ seam-aware authority
→ bounded mobile construct
```

P8 не является prerequisite для первого playable seamless planet.

## ECO и research

ECO остаётся parallel research line и по умолчанию не блокирует P.

```text
research status alone != product blocker
```

Research может стать blocker только если:

- main явно регистрирует dependency;
- canonical owner из research становится prerequisite;
- ownership/directional audit показывает реальное пересечение;
- Work Order явно потребляет capability.

Поэтому LS3 может идти параллельно SM1/P7.

## Critical-path discipline до North Star

Приоритет:

```text
SM1 closure
→ P7 terrain mutation
→ V0 PLAYABLE SEAMLESS PLANET graphical acceptance
```

Не расширять critical path следующими направлениями без доказанного blocker:

- P8;
- arbitrary-N authorities;
- dynamic shard split/merge;
- новый transport;
- новый Gateway;
- full MRPF/HLOD;
- ECO product integration.

## Что делать агенту, когда пользователь говорит «продолжи основную ветку»

1. Прочитать machine `v0-product-train-policy.v1.json`.
2. Прочитать `CURRENT_PROJECT_FRONTIERS_RU.md`.
3. Прочитать `V0_PLAYABLE_SEAMLESS_PLANET_ROADMAP_RU.md`.
4. Определить current accepted predecessor и current runtime Work Order.
5. Если SM1 не принят — закрывать SM1, не начинать P7 runtime.
6. После SM1 acceptance — активировать P7 через полный successor protocol.
7. После P7 — выполнить отдельный North Star graphical acceptance.
8. Не превращать research donor в canonical product owner.
9. Любой второй canonical truth — STOP_AND_REPLAN.
10. При следующем review сравнить состояние с датированным progress snapshot.
