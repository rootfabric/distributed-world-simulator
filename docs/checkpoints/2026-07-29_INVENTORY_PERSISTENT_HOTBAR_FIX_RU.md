# Исправление persistent hotbar и drag overlay

База: `v16.8.4-data-plane-b0-message-bus-contracts`.

Ветка: `fix/inventory-drag-overlay-drop`.

## Результат

- Быстрая панель снова вынесена из окна инвентаря в отдельный постоянно видимый overlay.
- Все десять слотов закреплены в одной полупрозрачной строке высотой 72 px.
- Встроенная compatibility-панель внутри окна инвентаря скрыта.
- Hover-подсказки предметов отключены; подробные данные остаются в инспекторе.
- Drag-preview является `top_level`-элементом с максимальным `z_index` и рисуется поверх окон инвентаря и hotbar.
- Перетаскивание средней кнопкой переносит верхнюю половину стака.
- Отпускание полного стака вне меню выбрасывает его в мир.

## Проверка

- `tests/ui/test_inventory_ui_i0_architecture.gd`: 43/43 PASS.
- `tests/ui/test_inventory_ui_i1_interactions.gd`: 64/64 PASS.
- `git diff --check`: PASS.
