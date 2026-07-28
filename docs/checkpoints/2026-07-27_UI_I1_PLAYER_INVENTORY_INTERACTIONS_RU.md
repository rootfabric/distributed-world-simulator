# Checkpoint UI-I1 — рабочее меню предметов игрока

Дата: 27 июля 2026 года
Ветка: `feature/ui-i0-inventory-shell`
База этапа: `v16.3.2-ui-i0-boundaries`
Checkpoint: `v16.3.4-ui-i1-fix1`

## Цель

Завершить основной рабочий слой hybrid two-pane inventory без изменения
канонического Item Graph и низкоуровневой семантики `ItemTransferService`.

## Реализовано

### Быстрый перенос

```text
Shift + ЛКМ
```

Переносит весь стак между рюкзаком и реально открытым внешним контейнером.
Для `SLOTS`-контейнера сначала ищется слот, способный принять весь запрошенный стак.
Неполный совместимый стак не выбирается, если далее есть подходящий пустой слот.
Если ни один слот не принимает всё количество, whole-stack quick transfer отклоняется
без частичной мутации; перенос части остаётся доступен через split dialog.

При закрытом внешнем контейнере операция fail-closed и объясняет, что сначала
нужно открыть контейнер через `E`.

### Контекстное меню

ПКМ без перетаскивания открывает действия:

- осмотреть;
- перенести весь стак;
- перенести 1;
- перенести половину;
- перенести точное количество;
- назначить в первый свободный hotbar slot;
- назначить в конкретный hotbar slot `1–0`;
- выбросить 1;
- выбросить весь стак.

Недоступные hotbar slots отображаются disabled после доменного preview.

Старый RMB-drag остаётся экспертным shortcut: сначала выбирается цель, затем
количество.

### Split dialog

Добавлены:

- slider;
- numeric input;
- `1`;
- `Половина`;
- `Максимум`;
- Enter для подтверждения;
- Escape для отмены;
- явное имя предмета и контейнера назначения.

### Tooltip и inspect

Hover tooltip показывает:

- название;
- количество;
- массу единицы и всего стака;
- объём единицы и всего стака;
- теги определения.

`Осмотреть` закрепляет расширенный tooltip. В debug build дополнительно
показывается UUID.

### Feedback

Успешные операции показываются зелёным toast.
Ошибки показываются красным toast и локально внутри рамки целевого контейнера.

Preview недопустимого drop также передаёт user-facing reason в целевую панель.

### Выброс всего стака

В `ItemGameplayController` добавлен presentation-level метод
`drop_item_stack()` и общий `drop_item_quantity()`.

Они не мутируют Item Graph напрямую, а используют прежние:

```text
ItemTransferService.move_item
ItemTransferService.split_and_move
```

`G` сохраняет старую семантику — выбросить одну единицу выбранного стака.

## UI-I1 fix1 — whole-stack quick transfer

Исправлен блокирующий сценарий:

```text
источник battery ×4
slot 0 battery ×3 / max ×4
slot 1 пустой
```

Теперь preview пропускает slot 0 с headroom `1` и выбирает slot 1, который принимает
все `×4`. Если полного слота нет, команда возвращает
`QUICK_TRANSFER_WHOLE_STACK_NO_FIT` и не выполняет частичный merge.

Все transfer-toast формируются по `result.moved_quantity`, а не по устаревшему
количеству карточки до операции.

## Не изменено

- schema `ItemInstance`;
- schema `ContainerState`;
- persistence Item Graph;
- operation ledger;
- stack compatibility;
- relation `WORLD / CONTAINER / ATTACHMENT`;
- hotbar как дочерний SLOTS container;
- legacy inventory fallback.

## Тест

Добавлен:

```text
tests/ui/test_inventory_ui_i1_interactions.gd
```

Проверяет 61 условие:

- реальный Shift+LMB event;
- quick transfer BULK ↔ BULK;
- quantity conservation;
- hover tooltip;
- RMB context menu;
- inspect + Escape hierarchy;
- exact split и кнопки 1/half/max;
- invalid quick transfer в battery rack;
- выбор полного слота после раннего неполного совместимого стака;
- запрет скрытого частичного merge, когда ни один слот не принимает весь стак;
- toast по фактическому `moved_quantity`;
- локальную ошибку и error toast;
- назначение конкретного hotbar slot;
- drop one;
- drop all;
- уникальность memberships и валидность graph.

## Критерий приёмки

- старые item/UI tests зелёные;
- новый UI-I1 test зелёный;
- main scene regression зелёный;
- `BULK` и `SLOTS` не меняют доменную семантику;
- нет потерь, дублей и `OPERATION_ID_CONFLICT`;
- UI-I1 остаётся отдельной feature-веткой для последующего merge.

## Следующий этап

После приёмки UI-I1 feature-ветка может быть заморожена для merge.
`UI-I2` — поиск, фильтры, view-only сортировка и большие хранилища — может идти
параллельно с `v16.4 Foundation Gate + N0`, не блокируя архитектурный трек.
