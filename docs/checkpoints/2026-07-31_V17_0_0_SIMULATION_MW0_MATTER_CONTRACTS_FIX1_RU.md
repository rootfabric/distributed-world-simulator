# v17.0.0 — Simulation MW0 Matter Contracts fix1

Дата: `2026-07-31`
Статус поставки: `ACCEPTED`
Base checkpoint: `v16.10.6-architecture-a3-single-server-multiplayer`
Ветка: `feature/mw0-matter-contracts`
Checkpoint: `v17.0.0-simulation-mw0-matter-contracts`
Delivery: `fix1`
Build ID: `mw0-matter-contracts-fix1`

## Результат первой независимой проверки

Исходная поставка MW0 была корректно изолирована от production runtime, но focused-профиль обнаружил дефект нормализации:

```text
MW0: 95 failures / 2011 assertions
A3:  12/12 PASS
M6:  10/10 PASS
git diff --check: PASS
```

Падения концентрировались в двух контрактах:

- composition normalization/round-trip;
- `MatterBodyDefinition` normalization.

## Причина

`MatterContractUtils.normalize()` выполнял нормализацию через:

```text
canonical JSON encode → JSON decode
```

Для canonical hash это допустимо, но для типизированного in-memory DTO — нет. JSON не различает целое число и вещественное число с нулевой дробной частью. Godot после decode преобразует, например:

```text
1.0    → 1
1000.0 → 1000
```

Из-за этого checksum и canonical JSON оставались стабильными, но строгое сравнение `Dictionary` нарушалось:

- однокомпонентный состав терял `TYPE_FLOAT` у `mass_fraction=1.0`;
- `reference_radius_m=1000.0` превращался в `TYPE_INT`.

## Исправление

`normalize()` теперь:

1. полностью валидирует исходный контракт;
2. создаёт глубокую копию без aliasing;
3. проверяет возможность canonical JSON encoding;
4. проверяет неизменность canonical payload hash;
5. возвращает копию с исходными Variant-типами полей.

Transport/hash canonicalization остаётся в `canonical_json()` и `payload_hash()`. Она больше не используется как in-memory typed normalization.

Focused-тесты усилены без изменения числа assertions:

- body normalization дополнительно требует `TYPE_FLOAT` для `reference_radius_m`;
- composition property test требует `TYPE_FLOAT` для `mass_fraction`, включая значение `1.0`.

## Граница fix1

Изменение не затрагивает:

- поверхность Луны;
- runtime-миры;
- A3 gameplay path;
- M6 persistence/recovery;
- Item Graph;
- сетевые и presentation-контракты.

## Проверка

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_MW0_MATTER_CONTRACTS_TESTS.ps1
.\RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1 -GodotPath $godot
.\RUN_M6_DEDICATED_RECOVERY_TESTS.ps1 -GodotPath $godot
```

Ожидаемый focused gate:

```text
MW0 matter contracts: PASS
2011 / 2011 assertions
exit code 0
```

Точное сообщение runner является источником истины, если формат вывода отличается.

## Acceptance criteria

1. MW0 focused runner завершён с exit code `0`.
2. Все `2011` assertions проходят.
3. Composition normalization сохраняет значение и `TYPE_FLOAT`.
4. Body normalization сохраняет значение и `TYPE_FLOAT` для радиуса.
5. A3 остаётся `12/12 PASS`.
6. M6 остаётся `10/10 PASS`.
7. `git diff --check` остаётся `PASS`.

После независимого PASS delivery `fix1` можно принять как MW0 и перейти к `MW1 fixed-seed procedural asteroid sampler`.
## Независимая приёмка

```text
MW0: 2011/2011 PASS
A3:  12/12 PASS
M6:  10/10 PASS
git diff --check: PASS
```

Delivery `fix1` является принятой базой MW1.
