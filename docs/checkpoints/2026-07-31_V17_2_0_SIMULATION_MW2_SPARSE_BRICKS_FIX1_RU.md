# Checkpoint v17.2.0 — MW2 sparse bricks fix1

Дата: 2026-07-31
Ветка: `feature/mw2-sparse-bricks`
База: принятый `v17.1.0-simulation-mw1-fixed-seed-asteroid`
Delivery: `fix1`
Build ID: `mw2-sparse-bricks-fix1`
Статус: `CANDIDATE FOR INDEPENDENT REVIEW`

## Причина исправления

Исходная MW2-поставка не компилировалась в Godot 4.7.1 double-precision.

`MatterSparseBrickStore` объявлял метод:

```gdscript
func get(address: Dictionary) -> Dictionary:
```

`get` уже является базовым API `Object`. При вызове метода через экземпляр скрипта, созданный из `preload`, статический анализатор Godot не разрешал внешний member и завершал parsing ошибкой:

```text
Could not resolve external class member "get"
```

Дефект находился одновременно в focused-тесте и production `MatterQueryService`.

## Исправление

Публичный read API переименован:

```text
get(address) → get_snapshot(address)
```

Обновлены:

- `MatterSparseBrickStore`;
- `MatterQueryService`;
- focused MW2 test;
- архитектурная документация и delivery metadata.

Семантика хранения, deep-copy isolation, revision fences, content hash и query precedence не изменены. Число focused assertions остаётся `7470`.

## Граница поставки

Fix1 не меняет:

- адресацию cells и bricks;
- ghost sample layout;
- MW1 sampler;
- формат `MatterBrickSnapshot`;
- текущие runtime worlds;
- поверхность Луны;
- mesh, collision, persistence или network runtime.

## Требуемая независимая проверка

```text
MW2 focused:    7470 assertions PASS
MW1 regression: 3685 assertions PASS
MW0 regression: 2011 assertions PASS
A3 regression:  12/12 PASS
M6 regression:  10/10 PASS
parser/preload: PASS
git diff --check: PASS
```

До выполнения этой матрицы checkpoint остаётся кандидатом.
