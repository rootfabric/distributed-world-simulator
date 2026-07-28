# UI-I0 — компонентный каркас инвентаря

Дата: 27 июля 2026 года
Ветка: `feature/ui-i0-inventory-shell`
База: `v16.3.0-r2-inventory-ux`
Checkpoint: `v16.3.1-ui-i0`

## Реализовано

- `ItemInventoryUI` превращён в совместимый facade.
- Старый экран сохранён как `legacy_item_inventory_screen.gd`.
- Новый компонентный экран включён по умолчанию через
  `config/ui/inventory_ui.json`.
- Добавлены `InventoryViewModel` и `InventoryCommandFacade`.
- Добавлены отдельные TSCN-компоненты:
  - inventory screen;
  - container panel;
  - hotbar panel;
  - item cell;
  - stack split dialog;
  - tooltip;
  - context menu;
  - toast layer.
- `BULK` ViewModel отображает существующие агрегаты без фиктивных пустых слотов.
- `SLOTS` ViewModel сохраняет все настоящие фиксированные слоты.
- Сохранён старый публичный контракт, используемый `ItemGameplayController` и
  существующими тестами.
- Реализован явный legacy fallback.

## Не изменено

- Item Graph schema;
- ItemInstance и ContainerState;
- ItemTransferService;
- operation ledger;
- revisions;
- persistence;
- WORLD / CONTAINER / ATTACHMENT semantics;
- правила stack merge/split.

## Feature flag

Файл:

```text
config/ui/inventory_ui.json
```

Значения:

```text
component
legacy
```

Для временного override:

```text
PLANET_SIMULATOR_INVENTORY_UI=legacy
```

## Следующий этап

UI-I1 может развивать этот каркас без повторного изменения низкого уровня:

- Shift-click quick transfer;
- полноценное контекстное меню;
- явный split dialog;
- tooltip/inspector;
- toast и локальные ошибки;
- адаптивная компоновка крупных хранилищ.

## Дополнение v16.3.2 — видимые границы контейнеров

После ручной проверки UI-I0 обнаружено, что корректное отображение `BULK` без
фиктивных пустых слотов визуально не обозначало всю доступную область drop target.

Исправлено на presentation-уровне:

- рюкзак, открытый внешний контейнер и hotbar имеют постоянные рамки;
- каждой области назначен отдельный цветовой акцент;
- рамка охватывает всю доступную область, а не только существующие ItemCell;
- добавлена подпись роли контейнера;
- добавлена текстовая подсказка, куда переносить предмет;
- Item Graph, transfer service и container schema не изменялись.

Новый checkpoint: `v16.3.2-ui-i0-boundaries`.
