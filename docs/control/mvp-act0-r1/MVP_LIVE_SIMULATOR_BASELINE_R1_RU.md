# V0 MVP — Live Simulator Baseline R1

## Статус и основание

- Parent Work Order: `V0-MVP-R1-WO-001`.
- Project Epoch: `E2026-09-09-V0-MVP-R1`.
- Source product branch/head при уточнении: `feature/v0-mvp-playable-seamless-planet-r1 @ e80ff5a37f30729509f0a7d307cbb44f44dc23ac`.
- Decision: `HA-V0-MVP-LIVE-SIMULATOR-BASELINE-R1`.
- Решение пользователя: MVP должен завершаться не набором лабораторий, а рабочей базовой версией симулятора, где два клиента подключаются, перемещаются, копают, взаимодействуют с предметами, используют минимальную стройку и восстанавливают общий мир после reconnect/restart.

Это **refinement существующего MVP acceptance**, а не новая архитектурная foundation и не новый canonical owner. Уже независимо закрытые MVP1–MVP3 не переоткрываются. MVP4 продолжает текущий bounded scope общего канонического копания. Уточнение делает MVP5–MVP8 конкретной единой игровой цепочкой.

## Цель MVP

После acceptance должен существовать один запускаемый двухклиентский сценарий, который можно считать исходной живой базой дальнейшего DWS:

```text
start server/gateway/world
  ↓
client A + client B join same world
  ↓
move / see each other / cross A→B→A seamlessly
  ↓
equip real canonical tool
  ↓
dig canonical terrain
  ↓
receive exactly-once canonical material/item
  ↓
pick up / carry / drop / share item
  ↓
use existing Item Graph / inventory / container path
  ↓
construct one real minimal structure from canonical resources
  ↓
both clients see and collide with the same construction
  ↓
reconnect / server restart
  ↓
terrain + players + items + inventory/equipment + container + construction converge to the same durable canonical state
```

Операции должны выполняться через обычную live client input / production adapters. Test-only state injection, второй demo store или локальная client truth не засчитываются.

## Обязательные возможности

### 1. Подключение и персонажи

1. Два независимых клиента подключаются к одному gateway/world обычным запуском.
2. У игроков разные stable logical identities и live sessions.
3. Оба видят движение друг друга и один и тот же мир.
4. Уже принятый seamless `A→B→A` остаётся обязательной регрессией: без штатного reconnect/respawn, без подмены identity и без второго writer.

### 2. Каноническое копание и ресурс

1. Живой клиент использует реально экипированный canonical mining tool.
2. Сервер валидирует actor/session/authority/reach/operation и выполняет существующий P7/Matter path.
3. Terrain mutation виден обоим клиентам из канонической репликации.
4. Материал создаётся **ровно один раз** через существующий Item Graph / accepted output path.
5. Replay/duplicate/conflict не создаёт второй ресурс и не повторяет terrain mutation.

### 3. Минимальный полноценный item lifecycle

MVP обязан показать не только существование Item Graph, а обычное игровое использование предметов:

1. Канонический item имеет stable `item_instance_id` и один owner/truth path.
2. Игрок может получить/поднять предмет в inventory.
3. Игрок может выложить/drop предмет обратно в world.
4. Второй клиент видит тот же world item и может подобрать именно эту же identity.
5. Два клиента, одновременно пытающиеся забрать один предмет, получают один canonical winner; duplication запрещён.
6. Минимум один существующий shared container/storage path используется в live сцене: положить предмет, увидеть изменение другим клиентом, достать его обратно.
7. Inventory/equipment/container/world-item transitions сохраняют quantity/identity и exactly-once semantics.
8. Игрок должен пройти seam с непустым carrying/inventory state и сохранить предмет без потери/дублирования; после перехода предмет можно снова выложить в world на target authority.

Непрерывная rigid-body физика свободно летящего/катящегося предмета через authority boundary **не является требованием этого MVP**. Для R1 достаточно canonical pickup → carry across seam → drop. Это оставляет generic physical-entity handoff отдельным следующим физическим этапом.

### 4. Минимальная реальная стройка

Используется уже принятый Construction/P4 путь; новый Construction owner запрещён.

1. В live сцене доступен минимум один реальный buildable recipe/type из существующей системы.
2. Постройка требует канонические ресурсы из Item Graph; test/demo currency не допускается.
3. Сервер валидирует placement и выполняет atomic item debit + Construction commit.
4. Duplicate/replayed build operation не расходует ресурс и не создаёт второй объект повторно.
5. Оба клиента получают один и тот же construction identity/transform/state.
6. Постройка имеет реальное world presence: минимум collision/occupancy, а не только декоративный mesh.
7. После seamless перехода игрок по-прежнему может взаимодействовать с Item/Construction системами; handoff не должен оставлять gameplay path частично отключённым.

Полный building editor, structural engineering, vehicles/mobile constructs и P8 сюда не входят.

### 5. Persistence, reconnect и restart

MVP7 считается полным только если восстановление покрывает **всю базовую игровую композицию**, а не только terrain:

- terrain mutation/revision;
- player logical identity/session recovery contract;
- inventory;
- equipped tool;
- world items и их stable identities;
- shared container contents;
- Construction instances и их collision/world presence;
- operation dedup/replay state, необходимый для exactly-once после recovery.

После reconnect и после server/process restart два клиента должны прийти к одинаковому каноническому состоянию без ручной починки данных.

### 6. Late join / resync

Клиент, который подключился или восстановился после уже выполненных действий, должен получить текущий мир, а не только последующие deltas. Минимальный snapshot/resync обязан восстановить актуальные terrain, visible items, inventory/equipment для своего игрока, container и Construction state.

### 7. Bounded interactive workload

MVP8 должен быть не отдельным synthetic load test, а повторением живого игрового цикла двумя клиентами:

```text
move
→ seam crossing
→ dig
→ receive item
→ drop / pickup / container
→ carry item across seam
→ build
→ more movement/dig/item operations
→ reconnect one client
→ continue
→ restart world/server
→ restore and continue
```

Нужно доказать bounded queues/state, отсутствие бесконечного накопления replay/snapshot данных, отсутствие duplicate item/construction identities и сохранение responsive player control.

## Минимальные конфликтные случаи

Обязательные negative/concurrency controls:

- stale/wrong session or authority epoch;
- duplicate operation id and conflicting replay;
- два клиента одновременно подбирают один item;
- недостаточно ресурсов для build — mutation free;
- повтор build request — no duplicate construction/no second debit;
- disconnect во время уже committed операции — recovery не повторяет side effect;
- stale client snapshot/resync не становится новой canonical truth.

## Что именно должно быть сведено в одну сцену

MVP должен реально потребить уже существующие принятые владельцы/возможности:

- Gateway / networked gameplay / session identity;
- SM1 seamless authority handoff;
- P7 / Matter terrain mutation;
- canonical material output;
- Item Graph;
- inventory + equipment/tools;
- существующий container/storage interaction;
- Construction + real-resource debit/commit;
- persistence/replay/reconnect/restart.

Наличие отдельного старого PASS недостаточно: система должна быть использована в **текущем live two-client composition**.

## Привязка к текущим top-level predicates

### MVP5 — `MVP_EXACTLY_ONCE_MATERIAL_OUTPUT`

Закрывается только после live tool-gated dig → canonical output с duplicate/replay proof.

### MVP6 — `MVP_ITEM_CONSTRUCTION_PERSISTENCE_CONVERGENCE`

Минимальные sub-gates:

```text
MVP6_LIVE_ITEM_PICKUP_DROP_SHARED
MVP6_ITEM_IDENTITY_AND_QUANTITY_CONSERVED
MVP6_TWO_CLIENT_ITEM_CONTENTION_SINGLE_WINNER
MVP6_SHARED_CONTAINER_INTERACTION
MVP6_NONEMPTY_ITEM_CARRY_ACROSS_SEAM
MVP6_LIVE_CANONICAL_TOOL_EQUIPMENT
MVP6_REAL_RESOURCE_CONSTRUCTION_COMMIT
MVP6_TWO_CLIENT_CONSTRUCTION_REPLICATION
MVP6_CONSTRUCTION_COLLISION_PRESENT
MVP6_NO_PRIVATE_OR_DUPLICATE_TRUTH
```

### MVP7 — `MVP_RECONNECT_AND_RESTART`

Должен восстановить terrain + item/inventory/equipment/container + construction + necessary dedup state.

### MVP8 — `MVP_BOUNDED_INTERACTIVE_WORKLOAD`

Должен прогнать одну связанную live gameplay loop, а не набор независимых микротестов.

## Definition of Done для whole MVP

Whole MVP нельзя принять, пока fresh Reviewer/Verifier не могут независимо подтвердить один пользовательский сценарий:

1. clean start;
2. два live клиента;
3. движение и seamless;
4. equip tool;
5. dig;
6. exactly-once material;
7. pickup/drop/share/container;
8. перенос непустого inventory через seam;
9. реальная Construction из этих ресурсов;
10. видимость/collision у обоих клиентов;
11. reconnect;
12. server restart;
13. одинаковый восстановленный canonical state;
14. bounded repeated interactive workload;
15. full world/core regression + PC0 + exact evidence.

## Явно вне R1 MVP

Чтобы MVP оставался базой, а не бесконечной программой, в него **не входят**:

- ECO / генетика / экосистема;
- FABRIC experimental physics / BAKE / adaptive fidelity;
- continuous rigid-body cross-server migration, rolling projectile/item handoff;
- distributed contact-island physics;
- NPC/AI/combat/health;
- vehicles и `V0_P8_FIRST_MOBILE_CONSTRUCT`;
- portals / multi-world teleport;
- full WORLDGEN1;
- complex crafting/economy/logistics;
- WORLD PACKS/FILL как обязательный gate;
- polished production UI/UX.

Допустим минимальный функциональный HUD/Inventory/Build feedback, необходимый для выполнения live loop.

## Architecture / scope rule

Реализация сначала обязана композиционно переиспользовать существующих canonical owners через текущие MVP adapters. Нельзя создавать второй Item Graph, Construction store, Matter truth, persistence owner, authority manager или private client truth.

Если для одного из обязательных sub-gates доказанно требуется изменение existing canonical owner вне текущего Work Order allowed paths, это не разрешение на молчаливое расширение. Нужен отдельный bounded owner-native repair/scope amendment с точным blast radius и соответствующим Harness/Human gate. Product requirement остаётся обязательным; меняется только безопасный путь его реализации.
