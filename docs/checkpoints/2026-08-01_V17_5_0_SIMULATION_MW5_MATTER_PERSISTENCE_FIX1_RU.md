# Checkpoint v17.5.0 — MW5 Matter Persistence fix1

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery:   fix1
build_id:   mw5-matter-persistence-fix1
base:       v17.4.0-simulation-mw4-matter-mutations / fix3
branch:     feature/mw5-matter-persistence
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Причина fix1

Первоначальная поставка завершала focused runner, но первый checkpoint не публиковался:

```text
MW5 focused: FAIL (13 failures / 48 assertions / 9.914 s)
primary error: MATTER_PENDING_VERIFY_FAILED
```

`MatterPersistenceCodec.rehydrate_*()` вызывал strict DTO `validate(raw)` до реконструкции JSON-decoded чисел. Godot может декодировать declared `float` со значением `1.0` как `int 1`, поэтому raw DTO отклонялся до того, как constructor мог вернуть правильный Variant type.

## Исправленная последовательность

Для composition, snapshot, mutation request/result, mass ledger и material batch теперь применяется единый порядок:

```text
raw JSON exact-field/type/shape checks
→ canonical typed reconstruction through constructors
→ strict validation of reconstructed DTO
→ checksum validation of complete raw payload
→ reconstructed checksum == persisted checksum
```

Strict DTO validators больше не вызываются на raw JSON-decoded composition, snapshot, request, ledger, result или batch.

Вложенные `SimulationCellAddress` и `MatterBrickAddress` также пересобираются через constructors и проверяются по вычисленным `cell_id`/`address_id`, а не передаются в домен как raw Dictionaries.

## Защита от повреждения

Typed reconstruction не должна скрывать повреждение полей, которые constructor вычисляет заново. Поэтому после strict validation реконструированного DTO codec отдельно выполняет checksum validation полного raw payload. Изменённый raw field со старым checksum отклоняется.

## Focused regression

Focused test дополнительно выполняет реальный JSON encode/decode и rehydrate для:

- `MatterComposition`;
- `MatterBrickSnapshot`;
- `MatterMutationRequest`;
- `MatterMassLedger`;
- `MatterMutationResult`;
- `MatterMaterialBatch`.

Также проверяется отклонение request, у которого после JSON decode изменён `energy_budget_j`, но сохранён прежний checksum.

Точное число assertions фиксируется по первому независимому successful run fix1.

## Обязательная проверка

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_MW5_MATTER_PERSISTENCE_TESTS.ps1 `
    -GodotPath $godot `
    -TimeoutSeconds 300
```

После focused PASS требуется полная матрица:

```text
MW4: 187/187 PASS
MW3: 7519/7519 PASS
MW2: 7470/7470 PASS
MW1: 3685/3685 PASS
MW0: 2011/2011 PASS
A3:  PASS
M6:  10/10 PASS
git diff --check: PASS
```

## Граница fix1

Persistence schema, active/previous/pending protocol, generation chain, recovery coordinator и laboratory save policy не изменены. Fix1 меняет codec и focused regression, а также согласованную документацию/validation metadata.
