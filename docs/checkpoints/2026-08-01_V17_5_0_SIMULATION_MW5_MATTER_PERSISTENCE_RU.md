# Checkpoint v17.5.0 — MW5 Matter Persistence

```text
checkpoint: v17.5.0-simulation-mw5-matter-persistence
build_id:   mw5-matter-persistence
base:       v17.4.0-simulation-mw4-matter-mutations / fix3
branch:     feature/mw5-matter-persistence
status:     CANDIDATE FOR INDEPENDENT REVIEW
```

## Поставка

MW5 добавляет durable checkpoint и восстановление canonical matter state после полного перезапуска процесса.

Сохраняются:

- mutated `MatterBrickSnapshot` с revision >= 1; процедурные revision-0 caches не сохраняются;
- точные mutation request/result records;
- committed `MatterMaterialBatch`;
- body/generator/grid identity;
- generation chain и server tick.

Transient receiver reservations в checkpoint не допускаются.

## Repository

```text
active:   matter-state.json
previous: matter-state.previous.json
pending:  .matter-state.<pid>.<ticks>.pending.json
```

Pending-файл проходит write/read validation до atomic rename. Незавершённый pending игнорируется при recovery. Повреждённый или отсутствующий active допускает fallback на валидный previous; coordinator затем восстанавливает из previous новый authoritative active, чтобы generation chain могла продолжиться.

## Главные инварианты

1. Checkpoint checksum и component content hashes валидны.
2. Generator seed/version и body checksum совпадают с текущим runtime.
3. Grid checksum и cell level совпадают.
4. Journal committed results ссылаются на существующие snapshots и batches.
5. Orphan batch невозможен.
6. После восстановления exact replay не изменяет store, receiver или journal.
7. Тоннель остаётся видимым через continuous query после нового процесса.
8. Uncommitted pending generation не становится authoritative.
9. Generator mismatch не оставляет частично восстановленного состояния.
10. Неожиданный отказ применения component state запускает compensating rollback.
11. После previous recovery можно сохранить следующую generation.
12. Лаборатория восстанавливает checkpoint до запуска streamer и сохраняет checkpoint после каждого committed drill.

## Focused runner

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_MW5_MATTER_PERSISTENCE_TESTS.ps1 -GodotPath $godot -TimeoutSeconds 300
```

Linux:

```bash
GODOT_BIN=/path/to/godot.linuxbsd.editor.double.x86_64 \
MW5_TIMEOUT_SECONDS=300 \
./RUN_MW5_MATTER_PERSISTENCE_TESTS.sh
```

Focused test включает отдельные child processes для seed/save и fresh-process recovery.

## Regression

После focused PASS требуется:

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

Точное число MW5 assertions фиксируется по первому независимому successful run, а не по статическому подсчёту.

## Ограничения

- один JSON checkpoint для лабораторного scope;
- нет distributed/network recovery;
- нет incremental brick files и compaction worker;
- Moon runtime и production world catalog не изменены.
