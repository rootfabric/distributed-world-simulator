# FABRIC / SHIP-LAB-1 — летающая платформа: сборка, повреждение, ремонт

Дата планирования: 3 октября 2026.
Статус: **PLANNED / DOCUMENTATION ONLY / NOT IMPLEMENTED / NOT MAIN ACTIVATION**.
Основание: согласованный с пользователем полигон для проверки связи физики, строительства, взаимодействия и работы оборудования.
Основная карта: [FABRIC_CURRENT_ROADMAP_R4_1_R4_2_R5_RU.md](FABRIC_CURRENT_ROADMAP_R4_1_R4_2_R5_RU.md).

## 1. Зачем нужен полигон

Проверить не отдельные устройства и не постановочный полёт, а одну машину, собранную игроком из настоящих деталей. Поведение и отказ возникают из материалов, геометрии, связей, состояния и физических законов. Именованная сборка допустима; специальный solver для демонстрационной платформы — нет.

```text
Собрал → подключил → взлетел → переместил груз
→ повредил связь или деталь → получил физическое последствие
→ посадил или уронил → отремонтировал → снова взлетел
```

Первый законченный результат `SHIP-LAB-1.MIN`: собрать, взлететь, потерять одну управляющую связь, получить объяснимую реакцию, восстановить связь, снова управлять платформой. Это промежуточный результат, не полное закрытие полигона.

Полное `SHIP-LAB-1.CLOSE` дополнительно требует отрыва движителя, повреждения рамы, локального UNBAKE/ReBAKE, сохранения повреждённой машины, нового процесса восстановления, второй компоновки и независимой приёмки.

## 2. Место в исследовании и граница активации

Не менять порядок закрытия текущей линии:

```text
T13.5 → T14 CLOSE → T15 → T16 → R5.3 → R5.4 → R5 CLOSE → INTEGRATION-R6
```

T14 — наблюдение выбранного compiled subtree при сохранении compact execution; это не физический UNBAKE. T15 — локальное структурное расхождение экземпляра, instance fork и selective UNBAKE/ReBAKE. T12 Ship Matryoshka — функциональные подсистемы, не доказанный полёт корпуса.

Сценарии платформы становятся целевыми integration/falsification fixtures для T15/R5.3/R5.4: состояние повреждённого экземпляра, реакция связанных подсистем, сохранение физических величин и стоимость перестройки. Они не расширяют задним числом уже закрытые acceptance и не подменяют T15/T16.

Планирование, описание интерфейсов и bounded research prototype могут быть вынесены в отдельный Work Order до R6 после проверки фактических зависимостей; этот документ сам по себе не разрешает runtime dispatch. Проверка MIN не требует ожидать симуляцию 100k деталей. Product-перенос — только fresh current-main consumer в R6, с явной активацией, независимыми review/verifier и human merge gate. Полигон не становится неявным gate текущего V0 MVP.

## 3. Владельцы и переиспользование

Construction/ConstructAggregate владеет идентичностью, топологией, соединениями и изменениями конструкции; Matter — веществом и его свойствами; Item Graph — предметами и их размещением; существующие authority/network/persistence owners сохраняются. FABRIC и bake artifacts — вычислительные, удаляемые представления, не второй реестр мира.

Переиспользовать C13 geometry/collision projection, C14 structural/load proposals, C15 utility topology/capacity/priorities, structural aggregate compiler, BRIDGE-3/4, B0.6 и R5 capsules. Согласовать C15 allocation с физическим решением: нельзя дважды списывать энергию или держать две независимые истины о доступном питании. Роли coarse allocation и electrical solve фиксируются контрактом.

Ровно один активный physical writer на область/степень свободы. Godot presentation/collision adapter и FABRIC не интегрируют одно тело параллельно. Смена FULL/BAKE не является canonical mutation. Изменение canonical revision инвалидирует старое исполнение до следующего шага.

Обязательное физическое состояние для продолжения, включая заряд, температуру, запасы вещества и движение, хранится через принятый authoritative persistence contract; оно не должно существовать только в disposable bake cache.

## 4. Минимальная машина и физическая граница

Небольшая рама, источник энергии, несколько движителей, блок управления, независимые соединительные линии и перемещаемый груз. Количество/геометрия движителей фиксируются bounded Work Order, а не превращаются в правило kernel.

До кода выбрать и записать ограниченную модель движителя: вход энергии, необходимость рабочего тела, mass-flow, выход импульса, место реакции, тепловые потери, ограничения и stop/coast/fault modes. Электрический мотор сам по себе не создаёт тягу в вакууме. Не добавлять скрытые бесплатные силы или автоматическое спасение аппарата.

Тяга прикладывается в фактическом креплении. Общая сила и момент выводятся из размещения и центра масс. Груз, расход вещества, снятие и добавление деталей обновляют массу/центр масс/инерцию без двойного учёта. Перенос груза должен учитывать выбранный контракт внешней работы игрока, а не создавать импульс или энергию бесплатно.

На первом этапе детали выдаёт лабораторный fixture. Добыча, переработка и полное выживание не блокируют MIN. Установка, подключение, снятие и ремонт проходят через настоящие игровые команды, проверки расстояния/прав/совместимости и authoritative mutations. Подготовка fixture допускается отдельно; acceptance нельзя проходить прямой записью готовой исправной машины.

## 5. Этапы SHIP-LAB-1

Все этапы ниже **PLANNED**. Для каждого executable этапа нужны точный base, scoped Work Order, declared physical envelope, критерии и владельцы до реализации.

| Этап | Наблюдаемый результат | Обязательные проверки |
| --- | --- | --- |
| P0 — Contract and binding | Выбран физический floor и собрана карта владельцев | Canonical IDs, single writer, typed ports, units, persistence, failure/fallback policy, no second solver |
| P1 — Build and connect | Игрок собирает раму и устанавливает оборудование | Independent mount/signal/power/matter links; missing/wrong/stale connection rejects atomically; scene rebuild preserves source |
| P2 — Flight and cargo | Аппарат взлетает, управляется и реагирует на груз | Forces/moments from actual mounts; mass/COM/inertia; symmetric/asymmetric configuration; input/resource/energy accounting |
| P3 — First failure and repair | Разрыв управления, объяснимый отказ, восстановление и повторное управление | Explicit loss-of-signal policy; power and mount remain independent; no pose/velocity/charge reset; P0–P3 дают MIN |
| P4 — Operational fault matrix | Отдельные отказ питания, подачи вещества, перегрузка и перегрев | Typed fault cause, bounded degraded modes/load shedding, reserve/flow accounting; invalid numeric model is not a normal fault |
| P5 — Mount and frame damage | Движитель отрывается, рама повреждается или распадается | Physical load/strength criterion and canonical damage route; fragment motion; updated mass/inertia; actual line rupture/slack/retention contract |
| P6 — Selective detail and repair | Повреждённая область раскрывается, ремонтируется и снова упрощается | T15 instance fork; unaffected immutable models intact; causal neighbors update; no stale writer; conservation and valid state projection |
| P7 — Durability and generalization | Повреждённая машина переживает restart; вторая компоновка работает | New process, derived caches deleted, interrupted commits/retries, no duplication; another mass/layout/IDs without kernel patch |
| P8 — Independent closure | Весь цикл наблюдаем и воспроизводим | Exact source/evidence; independent physical oracle, Reviewer/Verifier, graphical + ordinary-command agent run; performance separately reported |

## 6. Различать виды повреждений

| Воздействие на один движитель | Ожидаемая причинная реакция |
| --- | --- |
| Потеря сигнала | Явно заданный safe state/timeout; питание, подача и крепление не исчезают автоматически |
| Разрыв питания | Нет новой электрической энергии; остаточная энергия, вращение и тепло эволюционируют по модели |
| Закрытие клапана, разрыв трубы или пустой бак | Подача/остаточный запас определяют тягу; утечка сохраняет mass ledger и меняет массу |
| Превышение мощности или температуры | Предусмотренный режим ограничения/защиты; недостаток тяги физически влияет на полёт |
| Разрушение крепления | Отдельный объект с собственной динамикой; его сила больше не действует на прежний корпус; линии рассматриваются независимо |
| Повреждение рамы | Пересчёт несущих связей и connected components; возможен progressive failure и split |

Не объединять всё в одну полосу HP или scripted `engine_off_after_hit`. Допустима команда контролируемого повреждения в debug-режиме через настоящий owner; она маркируется отдельно и не заменяет хотя бы один тест физического разрушения от нагрузки/удара. Guard может потребовать детализации до поломки; guard crossing не равен damage.

Аппарат не обязан пережить потерю движителя. Падение при реальном недостатке тяги — допустимое физическое следствие, а не автоматический FAIL. FAIL — нарушение принятого контракта, не сохранённая величина, необъяснимый отказ, stale/double execution или scripted rescue.

## 7. Операционный отказ не равен ошибке модели

Пустой бак, разряженная батарея, отсутствие команды, закрытый клапан, ограничение мощности и штатная защита должны иметь валидное следующее состояние. C15 load shedding и физическая supply/load coupling согласуются, а не конкурируют.

NaN, повреждённый state, неподдерживаемый режим, несходимость или STALE — отдельные диагностические причины. Нельзя продолжать заведомо некорректное решение. Нужны заранее заданные transition/fallback boundaries: отказ подсистемы не должен молча замораживать инерциальное движение всего мира. При отсутствии безопасного fallback возвращается явный fault, а не выдуманная физика.

## 8. FULL / BAKE / LOCAL UNBAKE / ReBAKE

Спокойная работа исполняется компактно только внутри доказанного envelope. Повреждение, изменение структуры или физически необходимая наблюдаемость раскрывают нужную область. Ремонт и стабилизация разрешают rebake с hysteresis, если безопасное сокращение существует; иначе сохраняется FULL/NO_SAFE_BAKE.

Локальная детализация не означает локальные последствия. Разрыв одной линии может изменить общую шину и все связанные нагрузки. Зависимые compact boundaries обязаны пересчитаться; при настоящей глобальной причинности refinement может расшириться. Фиксированный лимит «всегда 20 FULL деталей» не переносится из старого стенда в универсальное правило.

Смена представления сама не создаёт массу, заряд, тепло, линейный/угловой импульс или энергию. При физическом повреждении учитывать внешнюю работу, тепло разрушения, утечки и перенос ресурсов. Repair projection должна быть обоснована для совместимого state; копировать несовместимые storage scalars или придумывать скрытое состояние запрещено.

Визуальная детализация независима: открытая крышка или близкая камера не обязаны включать FULL physics. Физический sensor/interaction, требующий недоступной величины, может потребовать другой модели.

## 9. Наблюдение и агент

Полигон показывает фактические COM, направления и величины тяги, состояние четырёх типов связей, запас/расход ресурсов, температуру, нагрузку, причину ограничения, canonical revision, physical writer и FULL/BAKE/refinement path.

Пример диагностического смысла: «команда 70%; питание доступно; клапан закрыт; фактическая тяга 0». Это read model из результата расчёта, не отдельная логика, отключающая устройство.

Pause/step/replay, сравнение healthy/damaged/repaired и журнал command→event→mutation→effect используют один simulation clock. Автономный агент действует теми же gameplay-командами и читает snapshots/telemetry/screenshots. Прямая подмена state не считается playable acceptance. Управление GUI/MCP оформляется по существующему `docs/MCP_GODOT.md`.

## 10. Приёмка, бюджет и границы доказательства

До запуска зафиксировать численные допуски по declared floor, timestep и масштабам величин. Нужны независимый простой аналитический/численный ориентир, convergence/metamorphic проверки, перестановки IDs и физически эквивалентные компоновки. FULL/BAKE parity сама по себе не исключает общую ошибку обоих путей.

Сохранить HEAD/TREE, engine identity, команды/seed/config, исходные и конечные snapshots, hashes, события, raw logs, GUI evidence и результаты негативных случаев. Новые процессы для restart и replay; повреждение/duplicate/stale/reorder/crash-before/after-commit проверяются отдельно. Independent review и verification не выдаёт implementer.

R5.0 measurement contract: compile/index отдельно от hot tick; active states/equations/DOF, source/metadata visits, guard cost, boundary calls, local UNBAKE/ReBAKE, allocations/RSS/CPU, end-to-end tick median/p95/max, event spikes и amortization. Для сетевого продолжения — bytes/replication delay. Число деталей и нулевые leaf traversals не равны FPS; 100 экземпляров не равны доказанной игре со 100 кораблями. Конкретный runtime budget задаёт Work Order до acceptance, не повышается ради PASS.

## 11. Более широкая корабельная ветка

Это дальнейший план, не обязательное расширение первого MIN и не объявление production checkpoints.

| ID | Результат и зависимости |
| --- | --- |
| SHIP-0 | Canonical Construction ↔ FABRIC bridge для изменяемого корпуса; соответствует P0/P1 |
| SHIP-1 | Powered platform и первый fault/repair cycle; соответствует P2/P3 и MIN |
| SHIP-2 | Полные typed wiring/fluid/resource/fault сценарии; углубляет P1/P4 |
| SHIP-3 | Ходьба и взаимодействие на движущемся корпусе: вход/выход, кресло, прыжок, moving-frame velocities, груз |
| SHIP-4 | Functional/structural damage, split, selective detail, repair и durability; соответствует P5–P8 |
| SHIP-5 | Docking + минимальное выживание: согласование скоростей/соединений, ресурсные линии между аппаратами, кислород/температура; отсеки/шлюзы/утечки — отдельные bounded contracts |
| SHIP-6 | Два игрока: один управляет, другой перемещает груз/ремонтирует; authority handoff, reconnect/restart, no duplication; использует существующую сетевую архитектуру |

Persistence проверяется уже в P7 и при изменении state contracts, не откладывается целиком до SHIP-6. SHIP-3/5/6 могут требовать чужих capability/activation gates и не блокируют первый летающий research MIN автоматически.

Три уровня доступности: использовать готовую сборку → настраивать → конструировать из внутренних частей. Внутренние компоненты и материалы дают реальные свойства; микросборка не обязательна для первого полёта.

## 12. Documentation-only change boundary

Research base: `bb191ec4f610f1f879e48fa104ca3155464bbdc2` (закрытый T13.5).
Main control observed: `bfc335a86153a9f12e03563901d26c3253130d65`.
T14 frozen runtime `5a65e6d245fda85de50d1cf6c4a551c6240677be` не изменять.
Разрешённая текущая работа — дорожная карта и этот план. Runtime, tests, workflows, historical evidence, main registry/catalog, lease и authority не меняются. Документ не утверждает, что платформа реализована, запущена или принята. Следующий executable шаг определяется прежними gates и отдельным Work Order.
