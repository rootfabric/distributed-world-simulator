# Профили управления инвентарём

Базовый commit: `e00162c`.

Ветка: `fix/inventory-drag-overlay-drop`.

## Результат

Добавлены три переключаемых профиля поверх общей доменной системы предметов:

- `Как было` (`planet_default`) — прежние ЛКМ drag, Shift+ЛКМ, ПКМ drag и MMB drag;
- `Rust` (`rust_like`) — ПКМ выбирает точное количество до цели, ЛКМ кладёт весь виртуальный стак, ПКМ кладёт один, MMB переносит половину, Shift+MMB — треть;
- `7 Days` (`seven_days_like`) — ЛКМ берёт/кладёт весь виртуальный стак, ПКМ берёт половину и затем кладёт по одному.

Профиль можно выбрать в верхней панели инвентаря. Выбор сохраняется в UI preferences и может быть переопределён переменной окружения `PLANET_SIMULATOR_INVENTORY_PROFILE`.

В загруженных playground и lunar runtime профиль также переключается без перезапуска через Developer Console: `inventory.profile rust_like`. Команда без аргумента выводит текущий профиль; доступны `planet_default`, `rust_like` и `seven_days_like`.

## Архитектурные гарантии

- JSON-профили проходят schema validation и имеют детерминированный fallback.
- Временный стак хранится только в `InventoryTransferSession`.
- Начало переноса, отмена через `Esc` и смена профиля не меняют Item Graph или revision.
- Реальная мутация выполняется только через `InventoryCommandFacade`.
- Частичный drop за пределы UI теперь вызывает `drop_quantity()`, а не ошибочно выбрасывает весь стак.
- Внешний контейнер и persistent hotbar получают один и тот же активный профиль.

## Проверка

Итоговые результаты зафиксированы в `validation/inventory-interaction-profiles-validation.json`.

Фокусный запуск:

```bash
GODOT_BIN=/path/to/godot ./RUN_INVENTORY_PROFILE_TESTS.sh
```

Windows:

```powershell
.\RUN_INVENTORY_PROFILE_TESTS.ps1 -GodotPath "C:\Godot\godot.windows.editor.double.x86_64.console.exe"
```

## Итог тестирования

- editor import/script parse: **PASS**;
- профильный контракт и runtime: **69/69 assertions, PASS**;
- stack merge/split/drop: **61/61 assertions, PASS**;
- UI-I0: **43/43 assertions, PASS**;
- UI-I1: **71/71 assertions, PASS**;
- UI-I2: **55/55 assertions, PASS**;
- полный relevant item regression: **14/14 тестов, 1823 assertions, PASS**;
- unified planetary runtime: **PASS**;
- main scene CLI: **6/6 PASS**;
- `git diff --check`: **PASS**.

В UI-I1 остаются ранее существовавшие предупреждения teardown о незакрытых `CanvasItem`, `ObjectDB` и RID. Они не меняют exit code и не влияют на функциональные assertions этой поставки.
