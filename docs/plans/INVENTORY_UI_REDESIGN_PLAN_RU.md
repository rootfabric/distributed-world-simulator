# План переработки интерфейса инвентаря PlanetSimulator

Дата: 27 июля 2026 года
Базовый checkpoint: `v16.3.0-r2-inventory-ux`
Тип этапа: завершённый presentation scope, объединённый в `v16.4.1-foundation-inventory-merge`

Статус реализации:

- `UI-I0` — принят и объединён;
- `UI-I1` — принят и объединён;
- `UI-I2` + fix1/fix2 — принят и объединён;
- merge checkpoint: `docs/checkpoints/2026-07-28_V16_4_1_FOUNDATION_INVENTORY_MERGE_RU.md`;
- `UI-I3` отложен до N1/N2, чтобы batch commands сразу использовали authoritative replay semantics.

## 1. Цель

Создать простой, быстрый и масштабируемый интерфейс работы с предметами, который:

- остаётся понятным при первом открытии;
- ускоряет частые операции опытного игрока;
- одинаково корректно представляет `BULK` и `SLOTS` контейнеры;
- не меняет канонический Item Graph;
- не обходит `ItemTransferService`, revisions и operation ledger;
- готов к будущему authoritative server и сетевым подтверждениям;
- масштабируется от рюкзака и небольшого ящика до склада с сотнями стаков.

## 2. Решение по типу интерфейса

Принят основной паттерн:

```text
hybrid two-pane grid inventory
```

Его состав:

```text
Левая панель: рюкзак игрока
Правая панель: только реально открытый внешний контейнер
Нижняя панель: hotbar 1–0
Верхняя строка: поиск, фильтры, view-only сортировка, вместимость
Контекстный слой: tooltip, меню действий, split dialog, уведомления
```

Сетка остаётся основным представлением предметов, но drag-and-drop не является
единственным способом работы. Добавляются quick transfer, поиск, фильтры,
контекстные действия и позднее — безопасные batch-операции.

## 3. Что показывает исследование

Из предоставленного сравнительного отчёта принимаются следующие выводы.

### 3.1 Сетка остаётся лучшей базой

Сетка подходит для:

- личной сумки;
- небольших контейнеров;
- hotbar;
- предметов, которые игрок воспринимает как физические объекты.

Для больших хранилищ поверх сетки нужны поиск, фильтры и сортировка.

### 3.2 Drag-and-drop нужен, но не должен быть единственным путём

Основной жест сохраняется:

```text
ЛКМ drag → перенести весь стак
```

Дополнительный быстрый путь:

```text
Shift + ЛКМ → быстро перенести весь стак в противоположный активный контейнер
```

Дополнительные действия открываются через ПКМ, а не скрываются в обязательном
сложном жесте.

### 3.3 Базовые действия должны быть видимы

В tooltip и нижней legend отображаются доступные команды. Игрок не должен помнить
неочевидные комбинации без подсказки.

### 3.4 Поиск и фильтры нужны до появления большого склада

Их архитектуру следует добавить сейчас, но реализовать как presentation-only
проекцию. Поиск и сортировка не должны менять `ContainerState.item_ids` и revisions.

### 3.5 Hotbar — не отдельная копия предметов

Сохраняется текущая правильная модель:

```text
player_hotbar = дочерний SLOTS-контейнер рюкзака
```

UI только отображает этот контейнер.

## 4. Анализ текущей реализации

### 4.1 Что уже сделано правильно

Текущий низкий уровень уже поддерживает:

- `BULK` и `SLOTS`;
- auto-stack для `BULK`;
- отдельные фиксированные слоты;
- stack-on-stack;
- split-and-move;
- предварительную проверку допустимости переноса;
- operation ledger;
- optimistic revision;
- session-scoped operation IDs;
- контекстное открытие внешнего контейнера через взаимодействие;
- различный визуальный размер контейнеров;
- hotbar как реальный контейнер;
- полное сохранение Item Graph.

Поэтому переписывать `ItemTransferService`, `ContainerState` или persistence для
первой версии нового меню не требуется.

### 4.2 Основные UX-проблемы

#### BULK визуально похож на SLOTS

Рюкзак сейчас заполняется до фиксированной визуальной ёмкости пустыми ячейками.
Это создаёт ложное ощущение, что `BULK` имеет постоянные слоты.

#### UI строится одним крупным GDScript

`item_inventory_ui.gd` одновременно:

- создаёт всю сцену;
- управляет layout;
- строит item cells;
- открывает split popup;
- выполняет transfer callbacks;
- формирует tooltip;
- управляет статусными сообщениями.

Это затрудняет визуальную настройку и независимое тестирование компонентов.

#### Полная перестройка grid после каждой операции

Текущая очистка и повторное создание controls приемлемы для маленького демо, но
плохо масштабируются на сотни предметов и создают риск stale UI nodes.

#### Нет быстрого переноса

Для каждой частой операции требуется drag-and-drop.

#### Нет поиска, фильтров и view-only сортировки

При появлении большого склада интерфейс перестанет масштабироваться.

#### Ошибки показываются как постоянная строка

Нужны краткие toast-уведомления и локальная причина отказа возле цели.

## 5. Целевая архитектура presentation-слоя

```text
InventoryScreen
├── InventoryHeader
│   ├── SearchField
│   ├── FilterChips
│   ├── SortMenu
│   └── CapacityIndicator
├── PlayerContainerPanel
├── ExternalContainerPanel
├── ItemInspectorDrawer
├── HotbarPanel
├── ContextActionMenu
├── StackSplitDialog
└── InventoryToastLayer
```

### 5.1 Новые presentation-компоненты

Рекомендуемые сцены и скрипты:

```text
ui/inventory/inventory_screen.tscn
ui/inventory/inventory_screen.gd
ui/inventory/container_panel.tscn
ui/inventory/container_panel.gd
ui/inventory/item_cell.tscn
ui/inventory/item_cell.gd
ui/inventory/hotbar_panel.tscn
ui/inventory/hotbar_panel.gd
ui/inventory/item_tooltip.tscn
ui/inventory/item_context_menu.tscn
ui/inventory/stack_split_dialog.tscn
ui/inventory/inventory_toast_layer.tscn
```

Существующий `ItemInventoryUI` на переходном этапе становится facade, чтобы не
менять контракт `ItemGameplayController`.

### 5.2 InventoryViewModel

Добавить presentation-only модель:

```text
InventoryViewModel
├── player_container
├── external_container
├── hotbar
├── visible_items
├── search_query
├── active_filters
├── sort_mode
├── selected_item_id
└── pending_operation
```

ViewModel читает domain state и создаёт неизменяемое представление для UI.
Она не должна:

- менять Item Graph;
- менять порядок `item_ids`;
- создавать operation IDs;
- сохраняться в world snapshot, кроме необязательных пользовательских UI settings.

### 5.3 InventoryCommandFacade

Все UI-действия проходят через один facade:

```text
InventoryCommandFacade
├── preview_transfer
├── transfer_stack
├── transfer_quantity
├── quick_transfer
├── assign_hotbar
├── drop_item
├── inspect_item
└── open_context_actions
```

Facade вызывает существующие методы `ItemGameplayController`, которые используют
`ItemTransferService`. UI не должен напрямую мутировать контейнеры.

## 6. Правила отображения контейнеров

### 6.1 BULK

`BULK` отображается как динамическая сетка существующих стаков без постоянных
пустых слотов.

Показываются:

- занятые item cards;
- масса `current / maximum`;
- объём `current / maximum`;
- число отдельных стаков, если есть limit;
- общий drop target на фоне панели;
- отметка `Автостак`.

Пустые карточки не показываются, потому что они не являются реальными слотами.

### 6.2 SLOTS

`SLOTS` отображается как настоящая фиксированная сетка.

Показываются:

- все слоты, включая пустые;
- номер или назначение слота;
- ограничение слота через icon/tag;
- причина запрета при hover/drop;
- занятость `used / total`.

### 6.3 Размеры внешнего контейнера

Рекомендуемые профили:

| Размер | Ёмкость | Представление |
|---|---:|---|
| Малый | до 12 | 4 колонки, без scroll при возможности |
| Средний | 13–36 | 6 колонок, вертикальный scroll |
| Большой | 37–120 | 8 колонок, поиск и фильтры всегда видимы |
| Склад | более 96 результатов | recycled/virtualized cells, поиск обязателен |

Панель внешнего контейнера существует только при активной container interaction
session. Обычный `Tab` показывает только игрока и hotbar.

## 7. Матрица взаимодействий ПК

### 7.1 Основные действия

| Действие | Результат |
|---|---|
| ЛКМ drag | перенос всего стака |
| ЛКМ drag на совместимый стак | автоматическое объединение до лимита |
| ЛКМ drag на пустой SLOTS slot | отдельный стак в конкретном слоте |
| ЛКМ drag на BULK panel | auto-stack и перенос остатка |
| Shift + ЛКМ | быстрый перенос всего стака в противоположный контейнер |
| ПКМ | контекстное меню предмета |
| Double click | на первом этапе не используется |
| Drag за пределы окна | не удаляет и не выбрасывает предмет |
| Escape | закрывает context/split, затем inventory |

### 7.2 Контекстное меню предмета

Первый набор действий:

```text
Перенести весь стак
Перенести 1
Перенести половину
Перенести количество…
Назначить в hotbar…
Выбросить 1
Выбросить весь стак
Осмотреть
```

Действия появляются только когда допустимы.

Позже:

```text
Закрепить / Favorite
Пометить как мусор
Переместить все такие предметы
```

### 7.3 Разделение стака

Рекомендуемый основной путь:

```text
ПКМ → Перенести количество… → выбрать цель или количество
```

Допускается сохранить текущий быстрый RMB-drag как экспертный shortcut, но он не
должен быть единственным способом и не должен упоминаться как базовое действие.

Split dialog:

- slider;
- numeric input;
- кнопки `1`, `Половина`, `Максимум`;
- Enter — подтвердить;
- Escape — отменить;
- исходный и целевой контейнер явно подписаны.

## 8. Быстрые операции

### 8.1 UI-I1

Реализовать:

- Shift-click whole-stack transfer;
- кнопки `Взять всё` и `Положить всё` пока не добавлять;
- quick transfer выбирает только противоположный открытый контейнер;
- при закрытом внешнем контейнере Shift-click может назначать в первый допустимый
  hotbar slot только через отдельную настройку; по умолчанию ничего не делает.

### 8.2 UI-I2

После появления batch command contract:

- `Взять всё`;
- `Положить всё`;
- `Переместить все совпадающие`;
- multi-select;
- `Deposit all materials`-подобные операции.

Batch-операции нельзя реализовывать как набор несвязанных UI mutations. Нужен
доменный transaction/batch command с одним operation ID и однозначным result.

## 9. Поиск, фильтры и сортировка

### 9.1 Поиск

Поиск работает по:

- display name;
- definition ID;
- tags;
- пользовательскому имени;
- будущим component labels.

### 9.2 Фильтры первой версии

```text
Все
Ресурсы
Инструменты
Контейнеры
Монтируемые
Аккумуляторы
Строительство
```

Фильтры строятся из tags и не требуют изменения item schema.

### 9.3 View-only сортировка

Режимы:

```text
По имени
По типу
По количеству
По массе
По объёму
Недавние операции
```

Сортируется только `visible_items` во ViewModel. Канонический порядок контейнера
не меняется, поэтому:

- не меняются revisions;
- не создаются operation ledger entries;
- не нужен Undo Sort на первом этапе;
- сетевой сервер не должен знать о выбранной сортировке.

## 10. Tooltip и Item Inspector

### 10.1 Краткий tooltip

Показывает:

```text
Название
Количество
Масса одного / всего
Объём одного / всего
Теги категории
ЛКМ drag / Shift-click / ПКМ
```

### 10.2 Inspector drawer

По клику или действию `Осмотреть` открывается боковая карточка:

- полный UUID только в debug mode;
- components;
- состояние/заряд/прочность;
- relation;
- вложенный container summary;
- attachment/placement capabilities;
- доступные действия.

## 11. Визуальная система

### 11.1 Состояния item cell

Использовать только локальные и понятные состояния:

```text
normal
hover
keyboard focus
selected
valid drop target
invalid drop target
pending operation
locked/favorite (позже)
```

Не подсвечивать все пустые ячейки одновременно.

### 11.2 Цвет не является единственным сигналом

Каждое состояние дублируется:

- рамкой;
- icon;
- текстом/tooltip;
- формой маркера.

### 11.3 Масштаб

Минимальный размер item cell для ПК:

```text
56–64 px
```

UI scale должен быть настраиваемым независимо от viewport resolution.

## 12. Обратная связь об операциях

### 12.1 Toast

Успешные действия:

```text
Перенесено: Полевой маяк ×3
Объединено: +2, стак заполнен
Аккумулятор помещён в слот 2
```

Toast исчезает автоматически.

### 12.2 Ошибка возле цели

При недопустимом переносе:

- целевая панель кратко получает invalid state;
- рядом показывается локальная причина;
- предмет остаётся в source;
- общий status label используется только как fallback/debug.

Примеры:

```text
Слот принимает только аккумуляторы
Недостаточно объёма
Контейнер заполнен
Предмет нельзя разделить
Целевой стак заполнен
```

## 13. Производительность

### 13.1 Убрать полную перестройку UI

Перейти от `_clear_grid()` и полного создания controls к keyed reconciliation:

```text
item_id / slot_index → ItemCell
```

Обновлять только:

- изменившийся item;
- source container;
- target container;
- capacity indicators;
- selection/pending states.

### 13.2 Cell pool

Для больших контейнеров использовать pool/recycling controls.

### 13.3 Цели

На тестовой машине:

- 100 видимых стаков: refresh presentation менее 16 ms;
- 500 стаков с фильтром: ViewModel update менее 10 ms;
- отсутствие stale controls после 1000 последовательных transfers;
- отсутствие роста orphan nodes.

## 14. Совместимость с будущей сетью

UI не должен предполагать, что операция завершилась сразу.

Состояние команды:

```text
IDLE
PENDING
SUCCEEDED
REJECTED
```

На текущем offline runtime result возвращается синхронно, но интерфейс уже должен
уметь:

- временно блокировать source aggregate;
- показывать pending indicator;
- обработать `REVISION_CONFLICT`;
- выполнить refresh после authoritative result;
- не создавать локальную копию предмета для оптимистического drag.

Все новые UI-команды должны быть совместимы с будущим `NetworkCommandEnvelope`.

## 15. Низкоуровневые изменения

### 15.1 Не требуются на UI-I1

Не менять:

- `ItemInstance` schema;
- `ContainerState` schema;
- `ItemTransferService` semantics;
- Item Graph persistence;
- stack rules;
- hotbar relation;
- operation ledger.

### 15.2 Допустимые минимальные расширения

Можно добавить:

1. presentation DTO для preview result;
2. стабильные user-facing error messages по error codes;
3. optional UI metadata в `ItemDefinition.metadata`:
   - category;
   - icon key;
   - sort weight;
   - tooltip group;
4. batch transaction service только на позднем этапе UI-I2;
5. container access session до сетевой реализации, если потребуется проверка
   дистанции и закрытие контейнера при отходе игрока.

## 16. Этапы реализации

## UI-I0 — UX contract и компонентный каркас

Состав:

- зафиксировать interaction matrix;
- создать TSCN-компоненты;
- добавить ViewModel и CommandFacade;
- сохранить старый facade API;
- добавить demo fixtures разных контейнеров.

Критерий:

- новый UI отображает текущий graph без мутаций;
- старые item tests зелёные;
- presentation можно переключить feature flag.

## UI-I1 — основное рабочее меню

Состав:

- динамический BULK panel;
- настоящий SLOTS panel;
- two-pane layout;
- Shift-click quick transfer;
- контекстное меню;
- split dialog;
- tooltip;
- toast/error feedback;
- adaptive container size.

Критерий:

- все основные действия выполняются без знания скрытых режимов;
- player inventory не показывает внешний контейнер без `E`;
- quantity conservation и unique memberships сохраняются.

## UI-I2 — поиск и управление большим хранилищем

Состав:

- search;
- filters;
- view-only sort;
- cell pool/virtualization;
- item inspector;
- saved UI preferences.

Критерий:

- 500 стаков остаются управляемыми;
- search/sort не меняют Item Graph и revisions.

## UI-I3 — зрелые массовые операции

Выполняется после согласования с `Foundation Gate/N0`.

Состав:

- transactional batch command;
- multi-select;
- take all/deposit all;
- move matching;
- lock/favorite/junk;
- future storage affinities.

Критерий:

- batch имеет один operation ID;
- partial failure не оставляет граф в промежуточном состоянии;
- результат пригоден для authoritative server replay.

## 17. Тестовый план

### 17.1 Unit/ViewModel

- BULK не создаёт semantic empty slots;
- SLOTS создаёт точное количество slots;
- search/filter/sort дают корректную проекцию;
- сортировка не меняет domain order;
- capacity summary корректен;
- item tooltip формируется из definition/instance.

### 17.2 UI interaction

- LMB full-stack drag;
- Shift-click quick transfer;
- stack-on-stack;
- split 1/half/exact;
- cancel split;
- invalid slot reason;
- external container open/close lifecycle;
- hotbar assignment;
- Escape hierarchy;
- keyboard focus/search.

### 17.3 Domain invariants после UI сценариев

- quantity conserved;
- UUID не дублируются;
- item имеет ровно одну relation;
- container memberships уникальны;
- revision увеличивается ожидаемо;
- operation replay идемпотентен;
- save/restart сохраняет результат.

### 17.4 Container matrix

Обязательные fixtures:

1. маленький BULK backpack;
2. безлимитный BULK warehouse;
3. BULK с mass limit;
4. BULK с volume limit;
5. 4-slot battery rack;
6. 10-slot hotbar;
7. SLOTS с разными slot rules;
8. nested container item;
9. container с 100+ stacks;
10. read-only/rejected container.

### 17.5 Visual/manual acceptance

Проверить в 1280×720, 1920×1080 и ultrawide:

- panel не выходит за viewport;
- tooltip не перекрывает source/target;
- hotbar остаётся видимым;
- внешний контейнер не появляется без взаимодействия;
- error reason читается;
- UI scale 80/100/125/150%.

## 18. Acceptance gate

UI-redesign принят, когда:

- Item Graph schema не изменилась без отдельной ADR;
- все старые item/world regressions проходят;
- новый UI покрыт отдельной interaction matrix;
- `BULK` и `SLOTS` визуально различимы;
- внешний контейнер имеет contextual lifecycle;
- full-stack transfer доступен drag и Shift-click;
- split доступен через явное контекстное действие;
- search/filter/sort не мутируют domain;
- нет `OPERATION_ID_CONFLICT`, потерь и дублей;
- экран работает с контейнерами разного размера;
- presentation-код не создаёт обходных мутаций.

## 19. Место в общей дорожной карте

Фактическая последовательность:

```text
v16.3 UI-I0/UI-I1/UI-I2 feature line
+ v16.4 Foundation Gate/N0 line
→ v16.4.1-foundation-inventory-merge
→ N1 real transport vertical slice
→ N2 process harness
→ UI-I3 только поверх authoritative batch command
```

UI-I0–UI-I2 больше не являются отдельной долгоживущей веткой. Новые UI-функции
должны добавляться короткими ветками от текущего `main` и проходить общий
Foundation/network regression gate.

## 20. Конфигурируемые профили взаимодействия

Поверх общего `InventoryCommandFacade` введён presentation-слой профилей. Он меняет
только интерпретацию жестов, порядок выбора количества и цели, а также временный
стак на курсоре. `Item Graph`, контейнеры, operation ledger и persistence остаются
общими.

Профили загружаются из:

```text
config/ui/inventory_profiles/catalog.json
config/ui/inventory_profiles/planet_default.json
config/ui/inventory_profiles/rust_like.json
config/ui/inventory_profiles/seven_days_like.json
```

Приоритет выбора:

```text
явный runtime/test override
→ PLANET_SIMULATOR_INVENTORY_PROFILE
→ сохранённая пользовательская настройка
→ default_interaction_profile
→ planet_default
```

Доступные схемы:

- `planet_default` — полностью сохраняет прежние drag/Shift/ПКМ/MMB правила;
- `rust_like` — точный split до цели, виртуальный стак, половина и треть через MMB;
- `seven_days_like` — ЛКМ берёт/кладёт весь виртуальный стак, ПКМ берёт половину и кладёт по одному.

Для `planet_default` и `rust_like` перенос до подтверждения цели остаётся
presentation-only. Профиль `seven_days_like` использует другую, более строгую модель:
при подхвате предмет реально переводится во временный односекционный контейнер
курсора. Persistence блокируется до завершения операции, а `Esc` разворачивает
цепочку обменов и возвращает предмет в исходный слот. Это необходимо, чтобы
поддержать выкладывание по одной единице и замену занятого слота без расхождения UI
и Item Graph.

При первом включении `seven_days_like` рюкзак и каждый реально открытый внешний
BULK-контейнер мигрируют в доменный режим `SLOTS`. Миграция односторонняя,
транзакционная, проходит полную graph validation и сохраняет точные slot assignments.
За курсорную механику отвечает `InventoryCursorController`, за миграцию —
`InventorySlotModeAdapter`, а атомарный обмен реализован как `SWAP_ITEMS` в общем
`ItemTransferService`.
