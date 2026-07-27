# Решение по интерфейсу инвентаря после UX-исследования

Дата: 27 июля 2026 года
База: `v16.3.0-r2-inventory-ux`

## Решение

Для PlanetSimulator выбран:

```text
hybrid two-pane grid inventory
```

Основные принципы:

- grid-first для предметов;
- левая панель игрока и правая панель реально открытого контейнера;
- hotbar отдельной нижней строкой, но остаётся настоящим дочерним контейнером;
- `BULK` отображает существующие стаки, а не фиктивные пустые слоты;
- `SLOTS` отображает реальные фиксированные ячейки;
- drag-and-drop остаётся базовым действием;
- Shift-click добавляется как quick transfer;
- ПКМ открывает контекстные действия и явное разделение стака;
- поиск, фильтры и сортировка являются presentation-only;
- массовые действия откладываются до transactional batch command;
- Item Graph, persistence и transfer semantics не переписываются.

## Причина

Предоставленное исследование показывает, что сетка является наиболее привычной
основой для survival/loot интерфейсов, но чистый drag-and-drop плохо масштабируется.
Наиболее устойчивый рыноковый паттерн сочетает сетку с быстрым переносом,
контекстными действиями, поиском и фильтрами.

Текущий проект уже имеет правильный низкий уровень: `BULK/SLOTS`, stack/split,
preview, revisions, operation ledger и contextual external container. Поэтому
главная проблема находится в presentation и interaction design, а не в Item Graph.

## Граница работ

До `v16.4 Foundation Gate` рекомендуется выполнить только:

```text
UI-I0 component/view-model refactor
UI-I1 core inventory UX
```

Поиск и крупные storage tools можно продолжать параллельно с Foundation.
Transactional batch/multi-select следует выполнять после N0 command contracts.

Полный план:

`docs/plans/INVENTORY_UI_REDESIGN_PLAN_RU.md`.
