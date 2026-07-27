# Checkpoint UI-I2 — поиск и большие хранилища

Дата: 28 июля 2026 года
Checkpoint: `v16.3.5-ui-i2`
Feature-ветка: `feature/ui-i0-inventory-shell`

## Цель

Завершить безопасный presentation-only слой inventory feature перед merge gate:
поиск, категориальные фильтры, визуальная сортировка, постоянный инспектор и
ограниченное число UI-узлов для больших хранилищ.

## Реализовано

- поиск по display name, definition ID, tags и relation kind;
- фильтры `ALL / RESOURCE / TOOL / CONTAINER / BATTERY / MOUNTABLE / CONSTRUCTION`;
- view-only sort по имени, типу, количеству, массе, объёму и revision;
- SLOTS сохраняют физическую раскладку, несовпадающие элементы только затемняются;
- persistent inspector показывает canonical relation, components, mass, volume и revision;
- отдельный `InventoryPreferencesStore` в `user://planet_simulator/ui/`;
- cell pool в `InventoryContainerPanel`;
- page-window для более чем 120 projected aggregates;
- не более 96 активных карточек на virtual page;
- фильтрация и переход страниц переиспользуют существующий pool.

## Архитектурные ограничения

UI-I2 не изменяет:

- `ItemTransferService`;
- `ContainerState` schema;
- `ItemInstance` schema;
- `ItemGraphPersistence`;
- operation ledger;
- authoritative order `container.item_ids`;
- revisions при поиске, фильтрах и сортировке.

UI preferences не входят в item graph snapshot и не должны реплицироваться сервером.

## Acceptance

- editor import/parse;
- старые UI-I0 и UI-I1 tests;
- новый `test_inventory_ui_i2_large_storage.gd`;
- весь item/UI profile;
- main scene;
- manifest coverage 37/37;
- fresh overlay verification.

## Следующий шаг

После принятия UI-I2 ветка проходит merge gate. UI-I3 с multi-select и mass actions
не входит в этот checkpoint: он требует transactional batch command contract и
должен выполняться после Foundation Gate/N0 отдельной веткой.
