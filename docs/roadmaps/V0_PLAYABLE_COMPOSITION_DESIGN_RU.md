# V0 — Playable Composition Showcase

Статус: **DESIGN / PREPARATION ONLY**  
Владелец: **composition consumer; не владелец canonical truth**  
Design branch: `docs/v0-playable-composition-design`  
Будущая runtime branch: `feature/v0-playable-composition` — **НЕ СОЗДАВАТЬ до entry gate**  
Source main на момент открытия design lane: `1112d1f7cfad1df18fb3621a537e191e674848c6`

## 1. Зачем нужен V0

V0 — первый вертикальный срез, который отвечает не на вопрос «работает ли отдельная подсистема?», а на вопрос:

> **Можно ли уже собрать из принятых подсистем небольшой кусок настоящей игры, не создавая вторую архитектуру мира?**

К V0 проект уже имеет независимо доказанные куски: procedural terrain/geomorphology, playable character/equipment, Item Graph и контейнеры, Construction composition и масштабируемую C22 presentation-capability. V0 должен проверить их совместимость в одном игровом сценарии.

V0 не является новой foundation-программой. Он ничего не должен «переизобретать» и не становится владельцем terrain, character, items, construction, persistence или network truth.

## 2. Целевой игровой сценарий

Минимальная демонстрация V0:

1. Игрок загружается на процедурной поверхности.
2. Видит реальную небольшую базу/аутпост, собранную Construction-системой.
3. Идёт к базе по terrain с корректными collision/LOD/presentation.
4. Входит внутрь без teleport/scene replacement и без отдельной V0 world-state.
5. Открывает настоящий контейнер через существующий Item/interaction path.
6. Берёт предмет, переносит его между inventory/container и экипирует через существующий server-authoritative equipment contract там, где он применим.
7. Выходит из базы и обходит её, наблюдая масштабируемую C22 presentation без изменения canonical construction truth.
8. Перезапуск/восстановление не создаёт дубликатов item/equipment/construction state и не требует V0-specific persistence.

V0 считается полезным только если этот сценарий собран **композицией существующих владельцев**, а не набором демонстрационных копий систем.

## 3. Ownership rule — главное ограничение

| Область | Canonical owner | Что разрешено V0 |
|---|---|---|
| Terrain / geomorphology | G | читать и отображать accepted/current-canonical terrain contracts |
| Character presentation / equipment | CH + Item authority contracts | композиция существующего player presenter/equipment UI |
| Items / containers | Item Graph | использовать существующий identity/state/transfer path |
| Construction truth | Construction / T / C22 contracts | инстанцировать/показывать настоящую construction capability |
| Persistence | существующая persistence architecture | только использовать; не создавать V0 save format |
| Network | NX / canonical network layer | не создавать новую replication модель |
| Composition scene | V0 | orchestration, layout, test fixture, operator scenario |

Запрещено создавать `V0Inventory`, `V0Terrain`, `V0Character`, `V0Construction`, `V0SaveState`, `V0NetworkState` или любые эквивалентные вторые истины.

## 4. Entry gate для runtime V0

Design/preparation разрешены уже сейчас. Реальную `feature/v0-playable-composition` можно создавать только когда выполнено:

- `H0_0_SCAFFOLD_READY` — canonical;
- H0.1 closed-loop C22 pilot завершён;
- C22 capability интегрирована в current canonical main через отдельный разрешённый runtime merge gate;
- post-C22 standard PC0 = NON_RED;
- post-C22 directional PC0 не содержит blocking RED по областям V0;
- текущие G/CH/Item/Construction owners однозначно определены;
- V0 Work Order не требует foundation/schema change.

Если для V0 требуется новый canonical contract, работа останавливается и уходит владельцу соответствующей системы; V0 не исправляет архитектуру локальным обходом.

## 5. Не-цели V0

V0 **не включает**:

- G9 layered geology;
- MAT0 material ontology;
- ECO runtime integration;
- distributed server handoff;
- новую client prediction/reconciliation архитектуру;
- новый inventory/equipment implementation;
- procedural base generator;
- production-scale economy;
- AI settlement;
- ship/station reference frames;
- собственный persistence/save format;
- доказательство 1M construction ceiling.

Эти темы относятся к V1+ или своим foundation/runtime программам.

## 6. Этапы V0

### V0.0 — Composition Contract / Design Freeze

Цель: зафиксировать сцену, владельцев и входные контракты до runtime-ветки.

Нужно:

- перечислить конкретные canonical components/scenes/scripts, которые будут потребляться;
- проверить, что ни один owner не дублируется;
- определить минимальный outpost fixture;
- определить operator walkthrough;
- определить focused test matrix;
- определить visual/performance telemetry;
- получить control review на отсутствие foundation drift.

Checkpoint: `V0_0_COMPOSITION_DESIGN_READY`.

### V0.1 — Terrain + Player + Outpost Static Composition

Собрать минимальную единую сцену:

- procedural/current-canonical terrain;
- реальный player controller/presenter;
- небольшой real Construction outpost;
- корректные collision layers;
- единый world coordinate path;
- камера и player scale без V0-specific transforms, которые скрывают системную ошибку.

Acceptance:

- игрок может пройти от spawn к базе и внутрь;
- terrain и construction не расходятся визуально/коллизионно;
- нет duplicate world truth;
- scene startup/restart детерминирован в пределах существующих контрактов.

### V0.2 — Item / Container / Equipment Composition

Добавить:

- настоящий внешний контейнер;
- pickup/drop/transfer через canonical Item path;
- equipment UI/presenter через accepted CH path;
- визуальное подтверждение equip/unequip.

Acceptance operator flow:

`spawn -> approach base -> open container -> move item -> equip -> unequip -> close/reopen -> state remains coherent`.

Запрещено обходить Item Graph локальными Node-state копиями.

### V0.3 — Construction Presentation / LOD Composition

Подключить current-canonical C22 capability после её integration.

Проверить:

- одна construction semantic truth;
- local rebuild/presentation не изменяет canonical semantics;
- player movement/camera не вызывает ложных LOD или rebuild oscillations;
- nearby outpost remains visually coherent;
- rebuild telemetry не показывает runaway dirty-section loop;
- fixture остаётся достаточно маленьким для operator walkthrough, но использует production path, а не demo path.

### V0.4 — Restart / Recovery Smoke

V0 не вводит новую persistence систему, но обязан доказать композиционное восстановление:

- relaunch не создаёт duplicate items;
- equipment presentation совпадает с canonical state;
- construction fixture восстанавливается через существующий путь;
- V0 orchestration не является скрытым источником истины.

### V0.5 — Playable Showcase Acceptance

Финальная приемка V0:

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

Предлагаемый checkpoint: `V0_PLAYABLE_COMPOSITION_ACCEPTED`.

## 7. Focused test matrix

Минимальный автоматический набор:

1. `scene_boots_with_canonical_components`
2. `player_reaches_outpost_without_scene_handoff`
3. `construction_truth_has_single_owner`
4. `container_interaction_uses_item_graph_identity`
5. `equip_unequip_roundtrip_preserves_authoritative_state`
6. `presentation_rebuild_does_not_mutate_construction_semantics`
7. `restart_does_not_duplicate_item_or_equipment_state`
8. `v0_has_no_private_save_or_replication_truth`
9. `v0_diff_has_no_foundation_contract_changes`

Точные имена тестов могут отличаться; семантика этих девяти проверок должна сохраняться.

## 8. Operator graphical acceptance

Ручной проход должен быть коротким и воспроизводимым:

1. Запустить V0 fixture из чистого checkout.
2. Зафиксировать spawn, terrain, outpost и HUD/telemetry.
3. Дойти до базы обычным movement path.
4. Обойти базу снаружи и проверить seams/collision/presentation.
5. Войти внутрь.
6. Открыть контейнер.
7. Переместить предмет в inventory.
8. Экипировать и снять предмет.
9. Выйти из базы и изменить расстояние до конструкции, наблюдая presentation/LOD/rebuild telemetry.
10. Закрыть приложение, запустить снова и повторно проверить item/equipment/construction state.

Любая необходимость «починить для демо» данные напрямую в V0 scene считается finding против владельца системы, а не поводом создать V0-specific truth.

## 9. Performance / telemetry

V0 не вводит новый глобальный performance SLA, но должен собирать композиционные сигналы:

- frame time / visible hitch markers;
- construction rebuild count and duration;
- dirty-section count;
- presentation LOD/current representation;
- item operation latency там, где метрика уже существует;
- duplicate identity/recovery findings;
- scene startup/restart time;
- PC0 watched intersections.

Пороговые значения должны наследоваться от canonical owner tests. V0 не должен самовольно ослаблять их ради красивой сцены.

## 10. Branch / Work Order policy

Сейчас разрешена только design lane:

`docs/v0-playable-composition-design`

После entry gate:

`feature/v0-playable-composition`

Runtime V0 должен получить bounded Work Order с allowed paths преимущественно в composition fixture/tests/docs. Изменение owner runtime-файлов допускается только через отдельный owner-scoped Work Order или возврат задачи в соответствующую программу.

До H0.3 V0 **не должен быть вторым параллельным runtime worker**, если H0.1/H0.2 уже выполняет runtime Work Order.

## 11. Связь с дальнейшей roadmap

V0 — первый визуальный composition milestone, после которого последовательность может развиваться так:

`V0 Playable Composition -> V1 Persistent Planet Outpost -> V2 Seamless Two-Region World -> V3 Moving Ship/Station -> V4 Autonomous Settlement -> V5 Distributed Living World`.

V0 намеренно мал: его задача — доказать, что принятые сегодня подсистемы способны жить в одном playable world slice. Он является диагностическим мостом между subsystem acceptance и будущим persistent/distributed world, а не новой архитектурой поверх существующей.

## 12. Решение для текущего этапа проекта

Сейчас:

- вести V0 только как design/preparation lane;
- не создавать runtime branch;
- не менять registry/checkpoint catalog только ради V0 design;
- дождаться H0.1/C22 canonical integration;
- после C22 post-merge PC0 создать fresh-current-main V0 Work Order/branch;
- реализовать V0 одним bounded runtime slot;
- остановиться на `V0_PLAYABLE_COMPOSITION_ACCEPTED` до отдельного merge gate.
