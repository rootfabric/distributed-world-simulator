# Checkpoint v17.5.0 — MW5 Matter Persistence fix4

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery:   fix4
build_id:   mw5-matter-persistence-fix4
base:       v17.4.0-simulation-mw4-matter-mutations / fix3
branch:     feature/mw5-matter-persistence
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Причина fix4

MW5 fix2 и fix3 выровняли canonical serialization и точные file bytes, но `_finish_rehydration()` продолжал вызывать `MatterContractUtils.validate_checksum(raw)` для JSON-decoded DTO. После JSON integer-valued `float` восстанавливается как `int`, поэтому raw snapshot, ledger и mutation result вычисляли checksum в другом Variant-domain и отклонялись до применения уже построенного typed DTO. Независимый focused-run завершился `FAIL: 18 failures / 59 assertions / 10.682 s`.

## Исправление

Checksum-порядок теперь однозначен:

```text
raw JSON structural checks
→ typed reconstruction
→ strict validation of reconstructed DTO
→ compute_checksum(reconstructed typed DTO)
→ equality with checksum persisted in raw payload
```

`validate_checksum(raw)` для float-bearing persistence DTO запрещён. Raw payload остаётся источником сохранённого checksum и структуры, но не используется как checksum-domain. Повреждённый payload со старым checksum по-прежнему отклоняется, поскольку reconstructed typed checksum не совпадёт с persisted checksum.

## Focused-регрессия

Тест отдельно требует, чтобы после canonical JSON roundtrip:

- snapshot успешно восстанавливался и проходил `MatterBrickSnapshot.validate()`;
- mass ledger успешно восстанавливался и проходил `MatterMassLedger.validate()`;
- mutation result успешно восстанавливался и проходил `MatterMutationResult.validate()`;
- persisted checksum сохранялся в raw transport payload;
- canonical representation snapshot не менялась после rehydrate;
- stale checksum corruption отклонялась.

Exact raw-byte publication из fix3 не изменена.

## Обязательная проверка

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_MW5_MATTER_PERSISTENCE_TESTS.ps1 `
    -GodotPath $godot `
    -TimeoutSeconds 300
```

После MW5 focused PASS требуется полная regression-матрица:

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
