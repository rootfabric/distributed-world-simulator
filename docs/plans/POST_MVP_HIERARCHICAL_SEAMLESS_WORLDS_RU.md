# Post-MVP — объёмная бесшовность и иерархия областей

Статус: **POST-MVP ROADMAP AMENDMENT / NOT ACTIVATED / NO CURRENT MVP SCOPE EXPANSION**.
Уточнение R2: 16 сентября 2026. Детальное решение: [объёмная топология, размещение и безопасное переразбиение](POST_MVP_VOLUMETRIC_TOPOLOGY_DESIGN_RU.md).

Этот план определяет первое крупное направление после принятия `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`. Он не является текущим Work Order, не расширяет acceptance первого MVP и не разрешает post-MVP runtime mutation. До принятия PR в main это предложение, не канонический scheduler.

R2 уточняет прежний HS-план: «вложенные миры» означают непрерывное пространство с объёмными участками ответственности, а не портал/телепорт между отдельными сценами. Смысловая иерархия, spatial partition, server placement и reference frames разделены. Прежняя редакция сохраняется в Git; HS1–HS8 остаются плановыми обозначениями, не новыми dispatched checkpoint IDs.

## 1. Цель

От простого seam перейти к явному разбиению трёхмерного пространства, допускающему пещеру/подвал внутри региона, несколько участков на одном сервере и управляемое разделение нагрузки между серверами.

Эталонное описание мест:

```text
Space
  -> Planet
      -> Surface POI
          -> Cave / Basement / Dungeon
```

Это не дерево физических процессов. Пещера сохраняет ID и содержимое после split её обслуживания. Один сервер может обслуживать несколько участков; разные участки могут пользоваться одной системой координат.

Игрок проходит `Space -> Planet -> POI -> Dungeon -> POI -> Planet -> Space` движением по общему пространству без телепортации, пересоздания персонажа или смены клиентского gameplay transport. Новый проход, выкопанный через стену/потолок, работает без заранее объявленного входа.

## 2. Основной контракт

```text
ONE_CONTINUOUS_WORLD_SPACE
ONE_CLIENT_WORLD_CONNECTION
STABLE_PLAYER_AND_ENTITY_IDENTITIES
NO_NORMAL_GAMEPLAY_RECONNECT_OR_RESPAWN
EXACTLY_ONE_SPATIAL_PARTITION_PER_POINT_IN_DECLARED_COVERAGE
AT_MOST_ONE_ADMITTED_WRITER_PER_CANONICAL_STATE
CHILD_DELEGATION_SUBTRACTS_FROM_PARENT_EFFECTIVE_REGION
CANONICAL_ITEMS_AND_CARRYING_PRESERVED
SPATIAL_PARTITION != SERVER_PLACEMENT
SEMANTIC_ZONE != OWNERSHIP_REGION
REFERENCE_FRAME != SERVER_OWNER
VERSIONED_TOPOLOGY_ASSIGNMENT_AND_FRAME_EVIDENCE
STALE_OWNERSHIP_CANNOT_AUTHORIZE_CANONICAL_COMMIT
```

На барьере или при отказе допустима временная недоступность writer, но не двойная запись. Нормальная бесшовность и восстановление после аварии имеют раздельные latency/ready критерии. Ноль доступных writers не означает дыру в карте и не передаёт область родителю автоматически.

Spatial ownership не заменяет существующий aggregate/entity ownership. Для неделимой машины или конструкции на границе требуется явный domain contract; независимые physics copies не становятся совместными writers.

## 3. Слои и существующие foundations

Разделять координаты/reference frames, смысловые зоны, эффективное пространственное разбиение, назначение исполнителей и read-only interest/projections. Semantic и visibility overlaps допустимы; эффективные ownership-области не пересекаются. Priority смыслового слоя не выбирает server authority.

Переиспользовать WorldGraph, Directory/AUTHORITY, существующие spatial identities, Edge Gateway, SM1, MW9/MW10 и Item/Construction owners. `CONTAINS` подходит для делегирования; `OVERLAP` должен явно описывать свою семантику. Существующий `PORTAL_OR_TRANSITION` не удаляется из словаря WorldGraph, но портал/телепортация не является основой или доказательством этого этапа.

Начальное представление — статические half-open AABB и вложенные исключения, привязанные к выбранным стабильным границам канонического хранения. Произвольные пересечения ownership-siblings отвергаются до публикации. Дальнейшие CELL_SET/движущиеся области требуют отдельных доказательств.

## 4. Лестница HS1–HS8

### HS1 — Static Volumetric Topology

Собрать конечное объявленное покрытие с вложенными областями Planet/POI/Cave и явным остатком родителей. Доказать точное покрытие без дыр и наложений, half-open faces/edges/vertices, запрет циклов/повторных ID/невалидных bounds и fail-closed при неполном topology cache.

Разделить authoring-дерево и исполняемые непересекающиеся участки. В тестах обязательно два подвала один над другим, semantic overlap без смены owner и ownership overlap с отказом публикации. Случайные точки дополняют, но не заменяют точную геометрическую проверку.

### HS2 — Coordinates and Reference-Frame Contract

WorldAddress связывает instance/space, reference frame, координаты и требуемую временную/ревизионную привязку. Сначала доказать статический общий frame и согласованные преобразования Space/Planet/local frame; отдельная frame на каждый сервер не требуется.

Проверить position/orientation и применимую velocity semantics без скачка физического состояния. Render-origin shift не меняет canonical address. Движущиеся/вращающиеся ownership volumes и изменение transforms во время операции выделяются в последующую bounded стадию; статический PASS не доказывает их поддержку.

### HS3 — Static N-Authority Seamless Handoff

Запустить настоящие authority-процессы, Gateway и два клиента. До живого переразбиения доказать движение между заранее заданными соседними и вложенными объёмами, вход с разных сторон и возврат; затем четырёхуровневый маршрут на ограниченном стенде.

```text
same client WorldConnection
stable PlayerId / PlayerEntityId
normal reconnects = 0
respawns = 0
teleport used as seam substitute = false
admitted writers for the same canonical state <= 1
```

Player/carrying handoff использует существующий протокол; соседняя projection не получает права записи. Промежуточные участки быстрого движения проверяются по траектории, а не только по endpoint.

### HS4 — View, Interest and Collision Readiness

До пересечения границы подготовить нужные данные и collision. На поверхности возможны macro/celestial projections; внутри подвала не требуется detailed simulation всей планеты.

Проверить bounded ACTIVE/WARM/projection subscriptions, cleanup, отсутствие ghost-only collision proof и контролируемое поведение при неготовом получателе. Гистерезис удерживает interest/preload, но не меняет пространственного владельца точки в зависимости от направления подхода.

### HS5 — Items, Construction and Mutable Boundary

Проверить canonical carrying, pickup/drop, реальные ресурсы и Construction на границе объёмов. Использовать принятые результаты MVP как baseline, не переоткрывая их документационной правкой.

Обязательный ограниченный стенд: около 100 строительных элементов поперёк seam, два клиента, stable IDs/membership/transforms, canonical resource accounting, реальная collision, ADD/REMOVE/replay и поддерживаемые связи. Неделимая физическая группа сохраняет одного owner либо использует отдельно доказанный sharding.

Новый выкопанный вход/выход через стену или потолок пещеры не меняет ownership topology. Передача ранее изменённой породы не подменяется повторной генерацией baseline. Persistence roundtrip и loss/duplicate controls обязательны.

### HS6 — Cross-Volume Operations and Interaction

Через существующие CWIP и доменные transaction contracts доказать действие из A над B, footprint через несколько участков, согласованность времени/версий и единственный effect commit. Источник input, collision-domain owner и effect-owner не обязаны быть одним сервером.

Использовать MW9/MW10 и Item/Construction recovery там, где они подходят; сначала проверить API и scope. Пространственное разбиение команды не заменяет атомарность. Lost reply/retry сохраняют OperationId/result; тесты отвергают partial effect и двойную выдачу ресурса.

### HS7 — Controlled Placement, Split/Merge and Recovery

Этот этап открывается после статической композиции HS1–HS6 и требует собственного разрешённого bounded Work Order. Это ручное управляемое переразбиение, не автоматический балансировщик.

| Подэтап | Обязательное доказательство |
| --- | --- |
| HS7.A Placement | Несколько участков на одном сервере; migrate существующего участка без смены геометрии |
| HS7.B Split / merge | R -> R_left/R_right -> перенос части; обратное объединение; child-исключения сохранены |
| HS7.C Durable cutover | Snapshot/catch-up, barrier, проверенный fence, durable decision, activation и cleanup |
| HS7.D Fault matrix | Crash каждого участника на каждой фазе; stale process/route; lost reply; concurrent edit; abort/forward recovery |

Матрица VT01–VT24 в [design R2](POST_MVP_VOLUMETRIC_TOPOLOGY_DESIGN_RU.md) является обязательным входом планирования тестов. Особенно проверить split родителя через child, удаление делегирования как обратную миграцию, неподвижного игрока при смене assignment и команду, начатую до барьера.

Отказ child-сервера не даёт родителю его scope. Старые ownership tokens должны отвергаться на реальном canonical commit path, не только в Gateway. Неподтверждённая защита от stale writer блокирует активацию нового.

### HS8 — Four-Level Live Composition Acceptance

На небольшом стенде: два реальных клиента, Gateway и четыре authority-процесса для маршрута Space/Planet/POI/Dungeon. Все четыре логические области образуют непрерывное пространство, без teleport/scene-switch подмены. Масштаб стенда не означает production galaxy или готовый орбитальный gameplay.

Пройти полный маршрут и выполнить реальные item/Construction/Matter операции. Дополнительно проиграть контролируемую смену assignment и split/merge в присутствии клиентов, в том числе неподвижного, используя HS7. Проверить continuity, conservation, collision, replay, subscriptions и recovery. Dynamic fault pause измеряется отдельно от normal seam.

Нужны exact HEAD/TREE evidence, relevant full regressions, Project Control и независимые review/verification согласно активированному Harness-контракту. Документ/модель не являются acceptance.

## 5. Что остаётся за пределами первого объёмного этапа

Полный WORLDGEN1, все WORLD PACKS, production ECO/FABRIC, новые глобальные owners, arbitrary-volume physics, автоматическое размещение/Kubernetes, тысячи игроков и доказательство всех moving-frame случаев не включаются автоматически.

Порядок развития: статическая N-authority композиция -> управляемые split/migrate/merge -> наблюдение/оценка размещения -> автоматическое размещение позднее. Сам разрез не гарантирует ускорения; учитывать стоимость границ, cross-domain transactions и неделимые физические группы.

## 6. Место в post-MVP развитии

```text
CURRENT MVP ACCEPTED
  -> HS1-HS6: статические объёмные области и живые операции
  -> HS7: контролируемое размещение / split / merge / recovery
  -> HS8: четырёхуровневая игровая композиция
  -> дальнейшее расширение мира и масштаба
```

WORLDGEN1, NX/RF, контент и ECO/FABRIC остаются соответствующими направлениями развития через явные consumer contracts. Этот документ не создаёт искусственную обязательную цепочку `WORLDGEN1 -> NX7 -> NX8 -> RF -> NX9`, не переименовывает P8 и не меняет объявленную независимость P8/RF. Нужные prerequisites определяются конкретным этапом по main-owned control, а не названием большой research-линии.

## 7. Activation и состояние доказательств

Реализация разрешается только после принятия `V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE`, закрытия текущего MVP Work Order, определения exact accepted base, отдельного post-MVP activation/epoch и bounded Work Order. Публикация этого текста не удовлетворяет этим условиям.

Перед исполнением сверить настоящий status и capabilities существующих owners; specification candidate не равен runtime acceptance. Неизвестный или отсутствующий API фиксируется как gap, не восполняется demo-only store/координатором.

Уточнение R2 не изменяет текущий MVP6 или его acceptance: выполняющий его агент продолжает действующее поручение. Документы HS — направление и подробная матрица будущих обязательств, а не второй scheduler.
