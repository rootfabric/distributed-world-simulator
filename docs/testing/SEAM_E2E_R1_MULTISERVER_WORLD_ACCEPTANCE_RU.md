# SEAM-E2E R1 — Полная приёмка бесшовного распределённого мира

**Статус:** `PROPOSED / NOT_ACTIVATED / RELEASE_BLOCKING_AFTER_HUMAN_APPROVAL`  
**Владелец протокола:** main-owned SEAM/E2E test lane; product owners сохраняют свою authority, World Directory, M6, Item Graph и Construction.  
**Основание:** `main@ae9a669336d93b3497fa78e5bb6d8eb3a21a0211` на момент создания; при выполнении всегда делать fresh fetch, записывать точные HEAD/TREE и контрольный Godot.  
**Никакой автоматической активации gate, merge, ротации lease/registry или реализации новых владельцев этим планом не допускается.**

## 0. Что именно обязаны доказать

Для игрока существует **один мир**, хотя внутренне его обслуживают разные серверы. Он без ручной переподключения пересекает A → B → C → B → A; второй игрок одновременно находится под иной authority, остаётся видимым и может **не только наблюдать**, но и совместно действовать с первым через границу.

Критерии бесшовности одновременно:

- **NETWORK:** клиент держит один обычный игровой транспорт к Edge Gateway; Gateway меняет backend route без закрытия world session и без выдачи клиенту endpoint simulation server.
- **AUTHORITY:** на каждый переносимый domain ровно один canonical writer; Directory/fence/epoch — источник истины. После CAS старый владелец навсегда теряет право старой записи.
- **SIMULATION:** обе стороны используют один мир, систему координат, игровое время, идентичности, движение, коллизии и взаимодействия. Проекция чужой области доступна для наблюдения, но не для записи.
- **PRODUCT:** реальные Item Graph, рудные/terrain изменения, инвентарь, Construction/outpost и физические взаимодействия имеют единый canonical outcome. Второй игрок видит и использует тот же результат без дублей.
- **VISUAL:** не появляется незагруженный ландшафт, разрыв биомов/коллизии, пропажа чужого аватара, скачок камеры, респаун либо скрытый экран загрузки.
- **RECOVERY:** сбой сервера/сети не создаёт две истины, не теряет подтверждённые операции и не позволяет старому процессу воскресить полномочия.

Нельзя принять одну ось как доказательство остальных: зелёный R31 по авторитету ≠ реальная межсерверная игра; зелёный SM1 graphical lab ≠ product Earth + Quaternius + ItemGraph + Construction на двух машинах.

## 1. Физическая топология — обязательна для FULL_E2E

```text
                  Client 1 ──┐
                             ├──── WorldConnection ── Edge Gateway G1
                  Client 2 ──┘                              │
                                                    shared backend links
                                              ┌────────┼──────────┐
                                              ▼        ▼          ▼
                                         Authority A  B          C
                                         Host H1      Host H2    H1 or H3
                                          ACTIVE     WARM/ACTIVE  WARM/ACTIVE

              Canonical Directory / owner-fence oracle
              Item Graph + Construction + durable persistence owners
              (existing product systems; never additional E2E replicas)
```

* Минимум **3 независимых authority-процесса A/B/C**, **1 gateway-процесс**, **2 реальных графических Earth+Quaternius клиента**: всего минимум 6 разных OS-процессов.
* Минимум **две независимые машины/host boundary**; для финального доказательства backend A↔B либо G↔B обязательно проходит по ненулевому сетевому пути, не `127.0.0.1`. Лаборатория с 6 PID на одном PC допускается как ранний PRECHECK, но НЕ как `FULL_E2E_PASS`.
* Желательно три физических хоста и больше клиентов при дальнейшем масштабировании; обязательный минимум A/B/C уже предотвращает ложное принятие двухсерверного hardcode.
* Все процессы используют **один замороженный product HEAD/TREE**, совместимый build/protocol, один `world_id` и согласованные spatial frame/cell адреса. Client G1 endpoint стабилен при routine handoff. Gateway никогда не хранит canonical игрока/предмет/стройку.
* Для нормального перехода `ClientWorldTransportCount == 1`. Gateway failover — отдельный fault gate: допустимо восстановление транспорта с сохранением логической сессии, но не routine reconnect на каждой границе.
* Обязателен запуск реальной production Earth-game сцены и Quaternius визуализации, не только синтетический SM1 `sm1_6_graphical_client.gd` и не fallback capsule.

## 2. Матрица сквозных сценариев

Полный перечень и обязательные proof types зафиксированы машиночитаемо в:
`config/testing/seam-e2e-r1-acceptance.v1.json`.

| Gate | Эксперимент | Нельзя заменить |
|---|---|---|
| S01 | Реальные процессы и 2 host boundary | Два internal service на одном сервере |
| S02 | Один client↔Gateway transport; backend pivots | Смену IP игрового сервера |
| S03 | Игрок A→B→C→B→A, 10+ переходов в каждом направлении | A→B→A в одном процессе |
| S04 | Два игрока под **разными** owners видят движения и анимации друг друга у шва | Два avatar в одной authority |
| S05 | Игрок A роняет/передаёт ItemId через seam; игрок B под B-authority его подбирает/использует | Два inventory/mirror store |
| S06 | Игроки одновременно меняют **одну** конструкцию, пересекающую шов; collision/attachments корректны | Локальные несвязанные здания |
| S07 | Реальные удары/добыча/изменение terrain по обе стороны шва, единый resource ItemGraph delta и версия поверхности | Только animation/dust клиентом |
| S08 | Контакт/физическое взаимодействие двух игроков или переносимого физического объекта под разными owners даёт один канонический результат | Две несвязанные локальные физические копии |
| S09 | Непрерывны ландшафт, LOD/vegetation, физика, avatar и камера; независимые client-кадры | Наблюдение только координат |
| S10 | Directory CAS, stale-owner fencing, race pickup/drop/build, lost ACK, OperationId exactly once | Успешное «переключение флага» |
| S11 | Краш/рестарт source и target до/после commit, gateway restart/rehome, старый владелец fenced | Только graceful stop |
| S12 | Независимые сетевые impairment пути, partition, packet loss/reorder/jitter, изоляция slow client | Один ping test |
| S13 | 3 полных GUI-прогона ×120 с с нормативной клиентской/серверной телеметрией | Headless frame estimates |
| S14 | 30-минутный soak после зелёных safety/exact gates, реальные пересечения/взаимодействия | Пустой idle soak |
| S15 | Project Control non-red, новый независимый review+verifier exact HEAD/TREE и Human Gate | Автоматическая самоприёмка |

Все S01–S15 обязательны. Если производственный owner пока не умеет полноценную межсерверную коллизию, construction cross-border или межсерверную транзакцию, вернуть **`BLOCKED_NOT_IMPLEMENTED`**, создать узкий product Work Order и негативный falsifier. Не конструировать test-only owner, не симулировать локальную вторую истину.

### S03 / S04 — два игрока одновременно

Минимальная реальная последовательность:

1. A и B заходят через один Gateway в один Earth world. A находится под Authority A, B под Authority B; оба видят друг друга в полосе около границы A/B.
2. A идёт A→B, B одновременно двигается вдоль шва в обратную сторону. Оба input_sequence растут, у A переносится domain, B не теряет authority.
3. Игроки **оста́ются одновременно активными** по обе стороны шва: наблюдают движения, позы/animation-state, inventory/equipment/held ItemId. Нельзя просто скрыть remote player до следующей загрузки.
4. A проходит далее B→C, второй игрок остаётся в зоне интереса у границы B/C; взаимодействие между owners продолжается. Возвращение C→B→A должно оставаться бесшовным.
5. Повторить ≥10 transfer для **каждого направленного ребра** A→B, B→C, C→B, B→A; синхронные встречные crossing и collision-owner races включить как отдельные негативные тесты.
6. Подменить owner endpoint клиента или сделать forced respawn — falsifier ДОЛЖЕН стать RED; проекция чужого региона не имеет права записывать gameplay.

### S05–S08 — не только картинки, но канонические совместные действия

Игрок A добывает ресурс на стороне A, получает ItemId, пересекает шов; B под B-authority видит тот же предмет. A бросает его на стороне B, B подбирает и использует; A подтверждает исчезновение на земле и изменение inventory B. Один ItemId, одно место в графе, один committed OperationId, два независимых observer receipts.

Игроки строят одну связанную конструкцию через шов: A ставит опору, B крепит следующий блок, A удаляет/меняет соседний блок. Проверить relationship, ownership, collision, resource debit, сохранение и репликацию под обе authority. Два «похожих» локальных объекта — FAIL.

На граничной клетке земля/руда должна измениться один раз, canonical terrain/material revision и добытые объёмы совпадают на всех owners; повторённая ударная команда с тем же OperationId не добывает вторую порцию. Проверить обратное восстановление после рестарта B.

Физический контакт/общий переносимый объект, пересекающий границу, должен иметь **одного канонического resolver**. Если engine пока не поддерживает межсерверную физическую интеракцию — блокировать gate, а не подставлять proxy-only response.

## 3. Защита authority и отказоустойчивость

Точные точки fault injection: после source freeze, после target PREPARE, перед/после ownership Directory CAS, перед target activate, после target activate до source retire, потеря commit response, delayed old-owner ACK/snapshot, owner process kill/restart, Gateway kill/rehome, сетевой split-brain/partition.

Для всех этих ситуаций обязательны:
- ровно один ACTIVE writer на domain;
- монотонный `authority_epoch` и `route_revision`, корректный fencing token;
- WARM/SHADOW/OBSERVER writes = 0;
- старый A никогда не принимает canonical изменение после CAS;
- `OperationId` и `ItemId` стабильны, duplication/loss=0;
- подтверждение клиенту только после durable commit (`durable-before-ACK`);
- snapshot, replay, Construction и Item Graph после restart соответствуют единой канонической истории;
- cancel/competing transfer или потерянный ответ дают ровно один итог, не silent success.

Отдельно тестировать два независимых impairment пути: клиент↔Gateway и Gateway↔Authority; Gateway не должен повышать себя до canonical owner или перепривязывать игрока из-за старого cache route.

## 4. Визуальная непрерывность и точные метрики

R3C.3, NET-SMOOTH1 R3C.4 и CHAR2 остаются источниками существующих frame/movement измерений. На **реальной графической** конфигурации и в тех же окнах должны быть собраны:

| Метрика | Целевой лимит |
|---|---|
| Клиент / сервер frame p99 | ≤25 мс |
| Frame p99.9 | ≤50 мс |
| Клиент max frame gap | ≤100 мс |
| Серверный loop | ≥59 Гц, authoritative gameplay 20 Гц |
| Необъяснённая пауза движения около шва | ≤100 мс |
| Пропажа remote avatar после handoff | ≤100 мс |
| Пространственная коррекция/телепорт у шва | ≤0,25 м |
| Угловой скачок камеры от переноса | ≤3° |
| LAN p99 доставки cross-owner canonical effect другому игроку | ≤250 мс |
| Двойная запись/дубли/потери/ранний ACK | Ровно 0 |
| Phantom/missing seam terrain tile | Ровно 0 |

*Новые perceptual пороги 0,25 м / 3° / 250 мс являются **предлагаемыми acceptance targets**, а не измеренными возможностями движка; до formal activation подлежат отдельному ревью продуктовых requirements. Они намеренно записаны явно, чтобы исполнитель не мог сам выбрать удобную метрику после прогона.*

Метрика камеры должна отличать преднамеренный поворот мышью от непреднамеренной коррекции при handoff. Позиционный «прыжок» рассчитывать относительно ожидаемой траектории с учётом честного движения/физики, а не сравнивать две абсолютные позиции без `delta_t`. Каждый кадр у boundary связывать с `world_id`, `spatial_frame_id`, `seam_crossing_id`, `authority_epoch` и `frame_id`.

После функционального сценария — **три независимых полных GUI-окна по 120 с**, отдельно от pre-warm/reconnect/soak. Фальсификаторы: скрытое укорочение окна, отсутствие END, dropped trace, fallback avatar, duplicate authority, ошибка выбора frame stage — все должны дать FAIL/INCONCLUSIVE.

30-минутный soak запускать только после полной нативной и функциональной приёмки, без предварительной выдачи нового merge разрешения.

## 5. Иерархия доказательств и запрет ложного PASS

Старые сценарии полезны как **регрессии**, но не замена единой топологии:

- `RUN_V0_SM1_GRAPHICAL.sh` и `test_v0_sm1_graphical_handoff_processes.gd`: реально поднимают **два** authority-процесса, gateway и 2 графических laboratory clients; обычно localhost и SM1 worker script, а не full Earth+Quaternius product.
- `RUN_V0_SM1_CONCURRENT_CROSSINGS.sh`, `RUN_V0_SM1_RECONNECT_AFTER_HANDOFF.sh`, `RUN_V0_SM1_WORLD_MUTATIONS_AROUND_HANDOFF.sh`: подтверждают изоляцию и контроль handoff/fault.
- `NET-SMOOTH1 R31`: доказано A↔B внутри User1 secondary authority, настоящий продуктовый клиент, но **не физический multi-host owner process pivot**.
- `MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM`, `P7.5/P7.6`, `M6`, `MRPF` и `EDGE_GATEWAY_FABRIC_SPEC_RU.md` — обязательные архитектурные/regression источники.

Любой gate должен иметь `product_head`, `product_tree`, Godot version/SHA, process/host identity, raw `trace.jsonl`, независимый authority/Directory receipt, оба client evidence, SHA256SUMS и отдельные reviewer/verifier findings. Для некоторых gates дополнительно нужны screen recording + screenshots (не единственный источник истины).

**Минимум два различимых host IDs; PIDs достаточно различать как (`host_id`, `pid`).** Потребовать топологический снимок реальных TCP/UDP соединений Gateway↔Authorities, run_id и совпадающий `world_id` в приложении, не только список заявленных ролей.

Прохождение source contract/test fixture означает `SPEC_CONTRACT_PASS`, а не `SEAM_E2E_PASS`. Полная приёмка — только если **все S01–S15 на одном frozen интегрированном продукте подтверждены**, Project Control не красный, независимые Reviewer и Verifier дали PASS и human release gate одобрил.

## 6. Дорожная карта исполнения без нового runtime owner

- **E0 / TOPOLOGY:** launcher/test harness на 3 независимых authority процесса + Gateway + 2 real clients; двухмашинный preflight, shared `world_id`, fail-closed process evidence. Если production routing рассчитан ровно на два authority, это отдельный owner capability gap, не обходить в тесте.
- **E1 / TRANSFER:** production Directory/fencing A↔B↔C, stable gateway endpoint, input/replay sequence, A↔B and B↔C return; повторения и concurrent crossings.
- **E2 / CROSS-PLAYER:** AOI, remote Quaternius, движение двух игроков под разными владельцами, безопасная коллизия и передача одного предмета между игроками.
- **E3 / WORLD ACTIONS:** общая Construction across seam, mining/terrain modifications и реальные canonical physics/collision observers на всех затронутых owner.
- **E4 / FAULTS:** race/crash/restart/partition, lost reply and exact retry; 2-host impairment; без двойных writer.
- **E5 / PERF + SOAK:** Windows+Linux exact, 3×120s GUI, p99/p999/frame gaps, затем 30min soak; итоговый independent review+verifier.
- **E6 / CONTROL:** canonical owner принимает спецификацию в program acceptance, Project Control non-red, затем human gate для продуктового merge/release.

Каждый этап отдельный узкий PR с собственными falsifiers; перенос в `main` только по обычному product/control process. Существующая работа NET-SMOOTH1 R3C.4 продолжается параллельно и не закрывает SEAM-E2E автоматически.

## 7. Решение на дату фиксации

```text
SEAM_E2E_SPEC = DEFINED_CANDIDATE
SEAM_E2E_PHYSICAL_3_AUTHORITY_2_HOST_PRODUCT = NOT_YET_PROVEN
SEAM_E2E_TWO_PLAYER_CROSS_OWNER_GAMEPLAY = NOT_YET_PROVEN
SEAM_E2E_FULL_ACCEPTANCE = BLOCKED_PENDING_IMPLEMENTATION_AND_EVIDENCE
MAIN_MUTATION = NONE
AUTOMATIC_MERGE = FORBIDDEN
```

Это **не отказ от требования бесшовности**, а зафиксированный release gate: нет требуемой производственной функции или измерения — нельзя объявить «мир бесшовным».
