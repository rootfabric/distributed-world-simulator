# Checkpoint v17.5.0 — MW5 Matter Persistence fix2

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery:   fix2
build_id:   mw5-matter-persistence-fix2
base:       v17.4.0-simulation-mw4-matter-mutations / fix3
branch:     feature/mw5-matter-persistence
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Причина fix2

MW5 fix1 завершался быстро, но не публиковал первый checkpoint:

```text
MW5 focused: FAIL (19 failures / 55 assertions / 19.746 s)
primary chain: INVALID_PERSISTED_MATTER_SNAPSHOT -> MATTER_PENDING_VERIFY_FAILED
```

Подтверждены три связанные причины:

1. focused helper сериализовал DTO через `JSON.stringify(value)` без full precision;
2. repository писал full-precision JSON, но checksum вычислялся через отдельный canonical JSON path;
3. snapshot rehydration разбирала columnar channels в samples и повторно строила palette, что не гарантирует сохранение исходного checksum-представления.

Дополнительно `PROJECT_MANIFEST.txt` имел лишнюю пустую строку в конце.

## Единый persistence/checksum domain

Fix2 вводит один публичный encoder:

```text
MatterPersistenceCodec.encode_persistence_json(value)
    -> MatterContractUtils.canonical_json(value)
```

Его используют и `MatterStateRepository.prepare()`, и focused JSON roundtrip. Поэтому checkpoint-файл хранит именно ту canonical representation, по которой вычисляются DTO и checkpoint checksums. Отдельный обычный или full-precision `JSON.stringify()` для persistence больше не используется.

## Snapshot rehydration

`MatterBrickSnapshot` теперь восстанавливается без повторной сборки через sample list:

```text
raw structural checks
-> typed address and palette compositions
-> typed columnar geometry/property arrays
-> typed palette indices and flags
-> strict MatterBrickSnapshot.validate(typed snapshot)
-> raw checksum validation
-> reconstructed checksum equality
```

Сохраняются исходные channel schemas/encodings, palette order и все entries. Проверка checksum не ослаблена.

## Focused regression

Все DTO roundtrips используют canonical persistence encoder. Для snapshot добавлены отдельные требования:

- encoded payload не пуст;
- JSON-decoded raw snapshot проходит собственный checksum;
- typed rehydrated snapshot имеет исходный checksum;
- canonical representation после rehydrate совпадает с исходной;
- опубликованный active-файл без завершающего newline совпадает с canonical encoding checkpoint.

Corrupted request со старым checksum по-прежнему отклоняется.

Точное число assertions фиксируется только по первому независимому successful run fix2.

## Граница fix2

Persistence schema, active/previous/pending filenames, generation chain, coordinator semantics, mutation service и world catalog не изменены. Из production-кода изменены только codec и repository; test logic расширена snapshot regression.

## Обязательная проверка

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_MW5_MATTER_PERSISTENCE_TESTS.ps1 `
    -GodotPath $godot `
    -TimeoutSeconds 300
```

После focused PASS требуется полная regression-матрица:

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
## Результат independent review

Fix2 не принят: `MatterStateRepository.prepare()` добавлял `"\n"` после canonical encoding, а focused-тест скрывал этот байт через `strip_edges()`. Поэтому заявленная гарантия raw file bytes == canonical persistence bytes фактически не выполнялась. Исправление перенесено в delivery `fix3`; codec и snapshot rehydration из fix2 при этом сохраняются.
