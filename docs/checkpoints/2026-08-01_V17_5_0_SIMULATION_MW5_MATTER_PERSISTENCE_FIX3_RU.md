# Checkpoint v17.5.0 — MW5 Matter Persistence fix3

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
delivery:   fix3
build_id:   mw5-matter-persistence-fix3
base:       v17.4.0-simulation-mw4-matter-mutations / fix3
branch:     feature/mw5-matter-persistence
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Причина fix3

MW5 fix2 выровнял JSON encoder и checksum-domain, но `MatterStateRepository.prepare()` после canonical encoding добавлял отдельный байт `LF`:

```gdscript
encoded += "\n"
```

Focused-проверка читала файл как текст и вызывала `strip_edges()`, поэтому скрывала фактическое расхождение между опубликованными байтами и `MatterPersistenceCodec.encode_persistence_json(checkpoint)`.

## Исправление

Repository записывает ровно строку, возвращённую canonical persistence encoder, без завершающего newline и других framing-байтов. Определение durable bytes теперь однозначно:

```text
canonical persistence bytes
= encode_persistence_json(checkpoint).to_utf8_buffer()
```

Focused-тест читает active-файл через `FileAccess.get_buffer(FileAccess.get_length())` и сравнивает два `PackedByteArray`. `strip_edges()`, текстовая нормализация и повторная сериализация в этой проверке запрещены.

## Граница fix3

Persistence schema, checksum algorithm, typed rehydration, active/previous/pending protocol, generation chain и process worker не изменены. Из исполняемого кода изменён только один байт publication policy в repository; focused test изменён только для честной raw-byte проверки.

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
