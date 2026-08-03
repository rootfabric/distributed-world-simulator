# Checkpoint v17.3.0 — MW3 local meshing fix2

## Статус

```text
checkpoint: v17.3.0-simulation-mw3-local-meshing
delivery: fix2
build_id: mw3-local-meshing-fix2
base: v17.2.0-simulation-mw2-sparse-bricks / fix1
branch: feature/mw3-local-meshing
status: CANDIDATE FOR INDEPENDENT REVIEW
```

`fix2` закрывает оставшийся блокирующий дефект streamer, найденный после проверки `fix1`. Граница MW3 не расширяется: canonical matter MW0–MW2, Луна, production world catalog, persistence, network authority и mutation semantics не изменяются.

## 1. Причина дефекта

`MatterCellGrid.address_for_position()` возвращает канонический `SimulationCellAddress`:

```text
cell_id
grid_id
grid_revision
level
path
checksum
```

Streamer ошибочно обращался к несуществующему полю `address_id` в трёх местах:

- сравнение текущей observer cell в `_process()`;
- сохранение `_last_observer_cell_id` при refresh;
- построение ключей desired neighborhood.

Это приводило к пустому идентификатору и invalid dictionary access при `refresh_at_body_local_position()`.

## 2. Исправление

Все обращения к исходному spatial DTO переведены на `cell_id`:

```gdscript
var observer_cell_id: String = String(observer_cell.get("cell_id", ""))
_last_observer_cell_id = String(observer_cell["cell_id"])
desired_by_id[String(address["cell_id"])] = address
```

Внутреннее поле очереди сохраняет имя `address_id`:

```text
request.address_id = SimulationCellAddress.cell_id
```

Это внутренний ключ streamer, а не поле канонического `SimulationCellAddress`. Переименование очереди не требуется и не меняет внешний контракт.

## 3. Защита от повторения

Статическая проверка поставки требует:

- отсутствия `observer_cell["address_id"]`;
- отсутствия `observer_cell.get("address_id", ...)`;
- отсутствия `address["address_id"]` при обработке результата `MatterCellGrid.address_for_position()`;
- наличия ровно трёх чтений `cell_id` в соответствующем контуре;
- неизменной focused-топологии `7519 assertions`.

## 4. Тестовая матрица

```text
MW3: 7519 assertions
MW2: 7470 assertions
MW1: 3685 assertions
MW0: 2011 assertions
A3:  12/12
M6:  10/10
```

## 5. Критерии приёмки

`fix2` принимается только после выполнения всех условий:

1. `RUN_MW3_LOCAL_MESHING_TESTS` — `7519/7519 PASS`.
2. Streamer создаёт desired neighborhood из 27 cell при стандартном radius `1`.
3. Первый pending brick успешно классифицируется без failed state.
4. Перемещение observer меняет desired cell IDs и увеличивает generation.
5. Observer вне root корректно отклоняется.
6. Synthetic и real seam checks остаются ненулевыми и проходят.
7. MW0–MW2, A3 и M6 regression проходят.
8. `git diff --check` проходит.
