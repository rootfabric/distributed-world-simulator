# Checkpoint v16.2.0-r2-placement-debug-ui

## Исправление разделения стеков

Инвентарный UI теперь синхронно удаляет старые `ItemSlotControl` из дерева перед перестроением сетки. Ранее `queue_free()` оставлял старую ячейку активной до конца кадра: после выбора количества drag мог стартовать из старой ячейки и передать полное количество. При отказе выбранное количество сохраняется для повторной попытки, а в журнал выводится `inventory-transfer` с item/container/slot/quantity/error code.

`BULK` по-прежнему автоматически объединяет совместимые предметы. Чтобы получить два отдельных стека, часть нужно перенести в пустой фиксированный слот `SLOTS` — например, hotbar.

## Устанавливаемые предметы

`beacon_mount_base` теперь является обычным item aggregate с placement profile `planet_simulator.item_placement_profile.v1`. Высокоуровневый `ItemPlacementService` регистрирует фабрики по `kind`, выполняет surface query и восстанавливает presentation по сохранённому item graph. Текущий kind `MOUNT_SOCKET` создаёт socket для предметов с тегом `beacon`.

Установка выполняется из активного hotbar через `E`. Один экземпляр отделяется от стека, становится WORLD item и получает placement component. Само основание пока нельзя демонтировать; установленный маяк можно снять в рюкзак.

## Инструменты отладки

- `F10`: правая системная панель.
- One-click загрузка миров из `WorldCatalog`.
- Админская выдача каждого зарегистрированного предмета `×1`/`×100` в BULK-рюкзак.
- Консоль: Tab completion команд и контекстных аргументов; история `↑/↓` восстанавливает фокус и caret.
- `F`: круговой `OmniLight3D`, range 1000 м, без теней для предсказуемой стоимости.

## Тесты

- `test_item_stack_transfers.gd`: реальный UI payload после quantity popup и защита от stale controls.
- `test_item_placement_and_admin.gd`: placement, socket, beacon mount/detach, ×100 grant, save/restart.
- `test_console_system_menu_and_flashlight.gd`: completion, history focus/caret, F10 menu callbacks и flashlight.
