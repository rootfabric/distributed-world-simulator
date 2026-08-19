# V0 — Playable Composition Roadmap

Статус: **DESIGN / PREPARATION ONLY**  
Владелец: **composition consumer; не владелец canonical truth**  
Design branch: `docs/v0-playable-composition-design`  
Будущая runtime branch: `feature/v0-playable-composition` — **НЕ СОЗДАВАТЬ до H0.3 entry gate**  
Source main на момент открытия design lane: `1112d1f7cfad1df18fb3621a537e191e674848c6`

## 1. Зачем нужен V0

V0 — первая точка, где проект должен перестать доказывать только отдельные подсистемы и начать доказывать **небольшие законченные end-to-end игровые процессы**.

Главный вопрос V0:

> **Можно ли собрать из принятых canonical подсистем небольшой воспроизводимый playable scenario, не создавая вторую архитектуру мира?**

V0 является первым **composition/integration milestone**. Он не является новой foundation-программой, отдельной игрой, редактором сценариев или владельцем world truth.

К V0 отдельные capability могут находиться на разных стадиях зрелости. Для первого playable slice не требуется заранее завершить все будущие NET/GEO/MAT программы. Требуется только тот минимальный набор canonical contracts, который нужен конкретной ступени V0.

Ключевой переход проекта:

```text
SUBSYSTEM ACCEPTANCE
        ↓
COMPOSITION ACCEPTANCE
        ↓
PLAYABLE SCENARIOS
```

V0 считается успешным только если playable flow собран **композицией существующих владельцев**, а не набором демонстрационных копий систем.

## 2. Тактический critical path к V0

Текущий primary path фиксируется так:

```text
             CURRENT PRIMARY
                   │
                   ▼
             H0.1 / C22
                   │
                   ▼
              H0_1_PASS
                   │
                   ▼
      HUMAN: C22 runtime merge
                   │
                   ▼
            post-C22 PC0
                   │
                   ▼
         C22 MAIN_INTEGRATED
                   │
                   ▼
         GLOBAL-P0 R3 promotion
                   │
                   ▼
             post-R3 PC0
                   │
                   ▼
            H0.2 / NX.C1
                   │
                   ▼
         NX SOURCE_ACCEPTED
                   │
                   ▼
                 H0.3
      multi-runtime-worker scheduler
                   │
                   ▼
       H0_3_ORCHESTRATION_ACCEPTED
                   │
        ┌──────────┼──────────┐
        ▼          ▼          ▼
       NET       GEO/MAT     WT/WQ
    capability   capability  capability
     adapters     adapters    adapters
        │          │          │
        └──────────┼──────────┘
                   ▼
                 V0.0
       Composition Contract Freeze
                   │
                   ▼
                V0-S0
             Runtime Boot
                   │
                   ▼
                V0-S1
             World Scenario
                   │
                   ▼
                V0-S2
              Item Scenario
                   │
                   ▼
                V0-S3
            Network Scenario
                   │
                   ▼
     V0_PLAYABLE_COMPOSITION_ACCEPTED
```

### Главное тактическое правило

`H0.3` является последним обязательным runtime-foundation gate перед V0 runtime.

После `H0.3` V0 **не обязан ждать полного завершения** всех:

```text
NX7 / NX8 / NX9
MAT0
G9 / G10 / G11 / G12 / G13
```

Эти программы должны разблокировать и расширять конкретные V0 capabilities, но не превращаться в безусловный барьер для первого integrated slice.

Иначе проект рискует получить множество зрелых подсистем без ранней проверки их совместной жизни.

## 3. Scenario Contract

V0 должен исполнять небольшой декларативно описываемый scenario. На V0 не требуется GUI-редактор сценариев.

Минимальный conceptual contract:

```text
ScenarioSpec
├── scenario_id
├── seed
├── world/body fixture
├── runtime worker set
├── participants
├── spawn points
├── construction fixtures
├── items / containers
├── bootstrap state
├── allowed interactions
└── expected invariants
```

Конкретный serialization format определяется реализацией и существующими contracts. `ScenarioSpec` не получает право вводить новую canonical world schema.

V0 **исполняет/композирует** сценарии; он не становится владельцем terrain, items, character, construction, persistence или network state.

## 4. Ownership rule — главное ограничение

| Область | Canonical owner | Что разрешено V0 |
|---|---|---|
| Runtime orchestration | H0 / canonical runtime control | запускать accepted workers и lifecycle через существующий scheduler path |
| Terrain / geomorphology | G | читать и отображать accepted/current-canonical terrain contracts |
| Material semantics | MAT / canonical material owner | использовать только принятые material IDs/projections, когда они доступны |
| Character presentation / equipment | CH + Item authority contracts | композиция существующего player presenter/equipment UI |
| Items / containers | Item Graph | использовать существующий identity/state/transfer path |
| Construction truth | Construction / T / C22 contracts | инстанцировать/показывать настоящую construction capability |
| World Query / Work adapters | WT/WQ owners | потреблять canonical adapters, не создавать private query/work scheduler |
| Persistence | существующая persistence architecture | только использовать; не создавать V0 save format |
| Network | NX / canonical network layer | использовать accepted transport/authority contracts; не создавать новую replication модель |
| Composition scene | V0 | orchestration, layout, scenario fixture, operator flow, composition tests |

Запрещено создавать `V0Inventory`, `V0Terrain`, `V0Character`, `V0Construction`, `V0SaveState`, `V0NetworkState`, `V0Scheduler`, `V0MaterialRegistry` или любые эквивалентные вторые истины.

Если для V0 нужен новый canonical contract, работа останавливается и finding возвращается владельцу соответствующей программы.

## 5. Entry gate для runtime V0

Design/preparation разрешены уже сейчас.

Реальную `feature/v0-playable-composition` можно создавать только когда выполнено:

- `H0_0_SCAFFOLD_READY` — canonical;
- H0.1 closed-loop C22 pilot завершён и `H0_1_PASS` зафиксирован;
- C22 capability интегрирована в current canonical main через разрешённый runtime merge gate;
- post-C22 standard PC0 = NON_RED;
- `GLOBAL-P0 R3` promoted/canonical для текущего development epoch;
- post-R3 standard PC0 = NON_RED;
- H0.2 / NX.C1 завершён до `NX SOURCE_ACCEPTED` согласно current control path;
- H0.3 доказал multi-runtime-worker scheduler/orchestration и получил acceptance checkpoint;
- owners для G / CH / Item / Construction / NX / WT-WQ однозначно определены;
- существует минимальный capability set хотя бы для `V0-S0`;
- V0 Work Order не требует foundation/schema change.

### Entry gate не означает feature-completeness

Для старта `V0-S0` **не требуется** завершение `NX7–9`, `MAT0`, `G9–13`.

Каждый следующий V0 scenario имеет собственный capability gate. Это позволяет начать composition verification раньше и использовать V0 как ранний детектор архитектурных несовместимостей.

## 6. V0 proof ladder

### V0.0 — Composition Contract / Design Freeze

Цель: зафиксировать scenario contract, владельцев, capability gates и operator flows до runtime-ветки.

Нужно:

- перечислить canonical components/scenes/scripts, которые будут потребляться;
- проверить, что ни один canonical owner не дублируется;
- определить `ScenarioSpec` fixture;
- определить minimal worker set;
- определить capability matrix `V0-S0…S3`;
- определить focused test matrix;
- определить visual/network/runtime telemetry;
- получить control review на отсутствие foundation drift.

Checkpoint: `V0_0_COMPOSITION_DESIGN_READY`.

---

### V0-S0 — Runtime Boot Scenario

Первый composition proof после H0.3.

```text
ScenarioSpec
     ↓
H0.3 scheduler/orchestrator
     ↓
┌────────────┬────────────┬────────────┐
│ world/query│ network    │ item/query │
│ worker     │ worker     │ worker     │
└────────────┴────────────┴────────────┘
     ↓
READY
     ↓
controlled shutdown
```

Минимальный acceptance:

- scenario запускается из clean checkout;
- требуемые workers переходят в READY через canonical lifecycle;
- startup order не является скрытой correctness-зависимостью;
- failure одного worker диагностируется с owner/cause;
- shutdown controlled и не оставляет зависших runtime state;
- V0 не содержит собственного scheduler/lifecycle truth.

Checkpoint: `V0_S0_RUNTIME_BOOT_ACCEPTED`.

`H0.3` напрямую разблокирует этот сценарий.

---

### V0-S1 — World Scenario

Первый визуально playable world slice.

Минимальная композиция:

```text
procedural/current-canonical terrain
        +
real player controller/presenter
        +
small real Construction outpost
        ↓
walkable integrated world
```

Operator flow:

```text
boot
 -> spawn on generated surface
 -> walk to outpost
 -> walk around outpost
 -> enter outpost
 -> leave outpost
```

Acceptance:

- игрок появляется на настоящей procedural/current-canonical поверхности;
- движение использует production movement/world path;
- terrain и construction согласованы по coordinates/collision;
- переход внутрь/наружу не требует scene replacement или V0-private world state;
- C22/current construction presentation остаётся derived от canonical construction truth;
- camera/LOD не меняют canonical identity;
- startup/restart детерминирован в пределах существующих contracts.

Checkpoint: `V0_S1_WORLD_ACCEPTED`.

### Capability gate V0-S1

Нужны только пригодные для композиции accepted/current-canonical capabilities G + CH + Construction/C22.

`G9–G13` и `MAT0` не являются обязательными для S1, если S1 не использует их semantics.

---

### V0-S2 — Item Scenario

Добавляет настоящий gameplay roundtrip предмета.

```text
player
  ↓
world item / container
  ↓
pickup / transfer
  ↓
Item Graph / inventory
  ↓
equip or carry
  ↓
drop / transfer back
  ↓
world state
```

Operator flow:

```text
spawn
 -> approach outpost
 -> open real container
 -> take item
 -> transfer/equip
 -> close/reopen
 -> drop or return item
 -> verify identity/state
```

Acceptance:

- внешний контейнер настоящий, а не V0-local storage;
- pickup/drop/transfer идут через canonical Item Graph identity/state path;
- equipment presentation использует accepted CH/Item contract там, где применимо;
- world/item adapters используют canonical WT/WQ contracts, когда они требуются;
- нет duplicate Item identity;
- нет локальных Node-state копий как источника истины;
- close/reopen сохраняет согласованное authoritative state.

Checkpoint: `V0_S2_ITEM_ACCEPTED`.

### Capability gate V0-S2

S2 разблокируется минимальными item/world interaction adapters. Более глубокие material ontology, fabrication, mining и cross-domain transactions относятся к последующим сценариям и не должны искусственно блокировать базовый item roundtrip.

---

### V0-S3 — Network Scenario

Первый сетевой end-to-end composition proof.

Минимум:

```text
1 authoritative runtime/server
2 clients
1 generated world fixture
1 outpost
1 shared item
```

Operator flow:

```text
A + B connect
 -> both observe same world fixture
 -> A moves to item
 -> A picks item up
 -> B observes authoritative disappearance/ownership result
 -> A moves
 -> A drops item
 -> B observes authoritative new world state
```

Acceptance:

- оба клиента используют canonical NX connection/session path;
- own/remote player presentation не создаёт вторую gameplay truth;
- item operation имеет один authoritative outcome;
- другой клиент видит подтверждённый result без V0-specific replication;
- reconnect/restart smoke не создаёт duplicate item/player state;
- network failure/rejection диагностируется через NX contracts;
- V0 не вводит собственную authority map или replication protocol.

Checkpoint: `V0_S3_NETWORK_ACCEPTED`.

### Capability gate V0-S3

Требуется accepted/current-canonical network capability, достаточная для двух клиентов и item/player state composition.

`NX7` полезен, когда S3 требует physics authority profiles; `NX8` нужен для масштабирования interest/replication budget; `NX9` — для hardening/persistence/soak. Они не обязаны все быть завершены для самого первого двухклиентского S3, если существующий canonical NX path уже обеспечивает требуемые semantics.

## 7. Как параллельные программы разблокируют V0

После H0.3 development перестраивается с «каждая подсистема только сама по себе» на capability-driven composition.

| Программа | Ближайший вклад в V0 | Не должна блокировать |
|---|---|---|
| H0.3 | worker scheduling/lifecycle/orchestration | V0-S0 после acceptance |
| G current/G8 | walkable procedural surface | V0-S1 ожиданием G9–G13 |
| Construction/C22 | real outpost + scalable presentation | S1 ожиданием T2 scale ceiling |
| CH | playable embodiment/presentation | S1 ожиданием полного clothing/ECO polish |
| WT/WQ | item/world interaction adapters | S2 ожиданием будущего полного Work Fabric |
| Item Graph | identity/container/transfer/equipment truth | S2 private inventory shortcuts |
| NX.C2/current NX | two-client composition path | S3 ожиданием всех production-scale NX7–9 |
| NX7 | physics authority policy | базовый S0/S1/S2 |
| NX8 | interest/replication budgets at scale | первый 2-client S3 |
| NX9 | async persistence/hardening/soak | первый functional S3 |
| MAT0/G9 | shared material/geology semantics | базовый terrain walking/item roundtrip |
| G10 | volumetric terrain/caves/overhangs | базовый S1 |
| G11 | heterogeneous body recipes | базовый S1 |
| G12/G13 | scheduler/cache/provenance/detail freeze | ранний V0 proof ladder |

Правило для каждой новой branch-local задачи после H0.3:

> **Какой V0 scenario/capability эта работа разблокирует или делает надёжнее?**

Если ответа нет, задача не должна автоматически попадать в primary critical path.

## 8. Не-цели базового V0

Базовый V0 **не требует**:

- завершённого G9 layered geology;
- завершённого MAT0 material ontology runtime;
- ECO runtime integration;
- distributed server handoff;
- production-scale NX8 interest management;
- полного NX9 hardening;
- нового inventory/equipment implementation;
- procedural base generator;
- production-scale economy;
- AI settlement;
- ship/station reference frames;
- собственного persistence/save format;
- доказательства 1M construction ceiling;
- GUI scenario editor.

Эти capability относятся к следующим vertical slices или своим foundation/runtime программам.

При этом V0 не запрещает использовать уже принятые версии этих систем, если они доступны и не расширяют scope конкретного scenario.

## 9. Focused test matrix

Минимальный автоматический набор должен отражать proof ladder.

### V0-S0

1. `scenario_boots_with_canonical_workers`
2. `worker_lifecycle_is_owned_by_h0_runtime`
3. `scenario_shutdown_is_controlled`
4. `v0_has_no_private_scheduler_truth`

### V0-S1

5. `player_reaches_outpost_without_scene_handoff`
6. `terrain_and_construction_share_valid_world_mapping`
7. `construction_truth_has_single_owner`
8. `presentation_does_not_mutate_world_semantics`

### V0-S2

9. `container_interaction_uses_item_graph_identity`
10. `pickup_transfer_drop_roundtrip_preserves_identity`
11. `equip_unequip_roundtrip_preserves_authoritative_state`
12. `v0_has_no_private_inventory_truth`

### V0-S3

13. `two_clients_observe_one_authoritative_item_outcome`
14. `remote_player_state_uses_canonical_network_path`
15. `reconnect_restart_does_not_duplicate_identity`
16. `v0_has_no_private_replication_or_authority_truth`

### Cross-cutting

17. `v0_diff_has_no_foundation_contract_changes`
18. `scenario_fixture_is_reproducible_from_clean_checkout`

Точные имена тестов могут отличаться; семантика проверок должна сохраняться.

## 10. Operator graphical acceptance

Финальный ручной проход должен быть коротким и воспроизводимым:

1. Запустить V0 scenario из clean checkout.
2. Проверить worker READY/lifecycle telemetry.
3. Зафиксировать spawn, terrain, outpost и HUD/telemetry.
4. Дойти до базы обычным movement path.
5. Обойти базу снаружи и проверить seams/collision/presentation.
6. Войти внутрь.
7. Открыть настоящий контейнер.
8. Переместить предмет в inventory/equipment через canonical path.
9. Вернуть/выбросить предмет в мир.
10. Подключить второй клиент.
11. Повторить pickup/drop одним клиентом и проверить authoritative observation вторым.
12. Выполнить reconnect/restart smoke.
13. Завершить runtime controlled shutdown.

Любая необходимость «починить для демо» canonical данные напрямую в V0 scene считается finding против owner-системы, а не поводом создать V0-specific truth.

## 11. Performance / telemetry

V0 не вводит новый глобальный performance SLA, но обязан собирать композиционные сигналы, доступные из owner-систем:

- runtime worker lifecycle / failure state;
- frame time / visible hitch markers;
- construction rebuild count and duration;
- dirty-section count;
- presentation LOD/current representation;
- item operation latency;
- network RTT/jitter/loss/correction counters, если доступны;
- duplicate identity/recovery findings;
- scenario startup/restart time;
- controlled shutdown result;
- PC0 watched intersections.

Пороговые значения наследуются от canonical owner tests. V0 не ослабляет их ради красивой сцены.

## 12. Branch / Work Order policy

Сейчас разрешена только design lane:

```text
docs/v0-playable-composition-design
```

Runtime branch разрешается только после H0.3 entry gate:

```text
feature/v0-playable-composition
```

Runtime V0 должен получить bounded Work Order с allowed paths преимущественно в composition fixture/tests/docs.

Изменение owner runtime-файлов допускается только через отдельный owner-scoped Work Order или возврат задачи в соответствующую программу.

До H0.3 V0 **не должен быть runtime worker** и не должен конкурировать с H0.1/H0.2 за foundation ownership.

После H0.3 V0 становится integration consumer и может развиваться по `S0 → S1 → S2 → S3`, не захватывая ownership у параллельных программ.

## 13. Final V0 acceptance

После `V0-S3` выполняется общий composition gate.

Acceptance:

- `V0_S0_RUNTIME_BOOT_ACCEPTED`;
- `V0_S1_WORLD_ACCEPTED`;
- `V0_S2_ITEM_ACCEPTED`;
- `V0_S3_NETWORK_ACCEPTED`;
- focused composition tests PASS;
- operator graphical walkthrough PASS;
- full applicable world/core regression PASS;
- standard PC0 NON_RED;
- directional PC0 NON_RED для затронутых owners;
- no blocking Human Attention;
- independent review подтверждает отсутствие duplicate truth;
- evidence привязана к exact tested head;
- draft PR открыт;
- STOP до отдельного runtime merge gate.

Финальный checkpoint:

```text
V0_PLAYABLE_COMPOSITION_ACCEPTED
```

## 14. Что становится возможно после V0

После V0 проект получает не «готовую игру», а работающую платформу для небольших сценариев на настоящих подсистемах.

Примеры следующих fixtures:

```text
small lunar outpost
+ 2 players
+ containers/items
```

```text
asteroid surface
+ generated terrain
+ resource item
+ transport to container
```

```text
planet valley
+ construction outpost
+ material-aware resource
+ persistent local mutation
```

Дальнейшее развитие может идти так:

```text
V0 Playable Composition
    ↓
V1 Persistent Planet Outpost
    ↓
V2 Seamless Two-Region World
    ↓
V3 Moving Ship / Station / Reference Frames
    ↓
V4 Autonomous Settlement / Economy / AI
    ↓
V5 Distributed Living World
```

Новые subsystem checkpoints после V0 должны по возможности проверяться через реальные composition scenarios, а не только изолированными labs.

## 15. Решение для текущего этапа проекта

Сейчас:

1. Не распылять primary runtime path до завершения `H0.1 → C22 merge → GLOBAL-P0 R3 → H0.2/NX.C1 → H0.3`.
2. Вести V0 только как design/preparation lane до H0.3.
3. Уже сейчас подготовить `ScenarioSpec`, capability matrix и acceptance semantics `V0-S0…S3`.
4. После H0.3 создать fresh-current-main bounded V0 Work Order/branch.
5. Сначала доказать `V0-S0`, не ожидая G9–13/NX7–9.
6. Затем подключать world, items и network только через canonical owner adapters.
7. Каждую параллельную NET/GEO-MAT/WT-WQ задачу привязывать к конкретному V0 capability или к явно более позднему milestone.
8. Любой новый foundation need возвращать owner-программе; V0 не делает local architectural workaround.
9. После `V0_PLAYABLE_COMPOSITION_ACCEPTED` остановиться до отдельного runtime merge gate.

Итоговая тактическая цель проекта после H0.3:

> **получить маленький, воспроизводимый, двухклиентский playable world slice на настоящих runtime/world/item/network подсистемах проекта — без V0-specific canonical truth.**
