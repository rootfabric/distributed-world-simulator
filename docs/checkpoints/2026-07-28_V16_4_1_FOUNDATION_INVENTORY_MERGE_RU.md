# Checkpoint v16.4.1-foundation-inventory-merge

**Дата:** 28 июля 2026 года
**Build ID:** `foundation-n0-fix1-ui-i2-integration`
**Основа:** `v16.4.0-foundation-n0-fix1`
**Объединённая ветка:** `feature/ui-i0-inventory-shell` (`5ff97f9`)

## Решение

Inventory feature line больше нельзя было оставлять параллельно Foundation:
ветки разошлись от `35cb5da`, после чего main получил 8 foundation/network
коммитов, а inventory — 6 UI-коммитов. Дальнейшее ожидание увеличивало бы API и
документационные конфликты.

Принято решение:

1. зафиксировать N0 fix1 отдельным commit поверх `115183c`;
2. выполнить `--no-ff` merge inventory-ветки;
3. сохранить обе линии истории;
4. закрыть найденный integration API gap;
5. принять единый checkpoint перед N1.

## Ревизия merge

Прямой merge дал 7 конфликтов:

- `PROJECT_MANIFEST.txt`;
- `README_RU.md`;
- `RUN_WORLD_REGRESSION_TESTS.ps1`;
- `docs/README_RU.md`;
- `docs/plans/NEXT_ITERATIONS_RU.md`;
- `scripts/app/lunar_app.gd`;
- `scripts/items/presentation/item_gameplay_controller.gd`.

Пять конфликтов относились к версии, runners и документации. В коде требовалось:

- сохранить текущий Foundation build/checkpoint;
- объединить `world_entity_count` и `inventory_ui_implementation` diagnostics.

После первого merge-test обнаружен дополнительный семантический разрыв:
`InventoryCommandFacade.drop_stack()` вызывал отсутствующий после Part 3 метод
`drop_item_stack()`.

## Исправление drop API

`ItemGameplayController` снова предоставляет:

```text
drop_item
drop_item_stack
drop_item_quantity
```

Это compatibility API, а не возврат старой архитектуры. Все операции проходят
через:

```text
ItemTransferService
→ WORLD relation
→ operation ledger
→ aggregate reconciliation
→ persistence/presentation synchronization
```

Partial drop использует `split_and_move`; full-stack drop использует
`move_item`. Container-item split остаётся запрещённым.

## Что объединено

- UI-I0 component shell;
- ViewModel и CommandFacade;
- contextual external containers;
- drag, quick transfer, context menu и split dialog;
- tooltip/toast/local rejection feedback;
- search, category filters и view-only sort;
- inspector и separate UI preferences;
- bounded 96-cell pool;
- operation-ledger generation cache invalidation;
- три UI regression suites.

Item Graph schema, Foundation aggregate и N0 DTO не изменены.

## Результаты проверки

```text
Editor import/parse:                         PASS
Inventory UI-I0:                     38/38 assertions
Inventory UI-I1:                     61/61 assertions
Inventory UI-I2:                     55/55 assertions
Item operation ledger:               89/89 assertions
Item Graph persistence:              30/30 assertions
N0 review regressions:               73/73 assertions
Kernel ports:                        52/52 assertions
Godot regression scripts:             55/55 PASS
Main scene:                         6 PASS, 0 FAIL
```

Тяжёлые runtime-наборы также проходят отдельно:

```text
test_unified_runtime_boot:                 PASS, 28.717 с
test_world_switch_during_generation:      PASS, 14.953 с
test_world_boot_matrix:                   PASS, 50.862 с
simulation-server process:                PASS, terrain drain 3756 мс
```

## Ветки и stash

После фиксации merge безопасно удалить локальные ветки:

```text
earth
feature/console-space-hotkeys
```

Они уже являются ancestors `main`.

`feature/ui-i0-inventory-shell` удаляется после push merge commit и проверки
remote main.

Stash audit:

- stash с `.godot/editor/filesystem_update4` — удалить;
- ранний `split UI-I0 inventory shell from master` — удалить после merge, его
  содержимое заменено принятыми UI-I0–UI-I2 коммитами;
- пустой terrain line-ending stash не содержит файлов и может быть удалён.

## Следующий этап

```text
N1 authoritative transport vertical slice
```

Первый remote сценарий должен использовать уже существующую item command path,
а не создавать отдельную сетевую модель предметов.
