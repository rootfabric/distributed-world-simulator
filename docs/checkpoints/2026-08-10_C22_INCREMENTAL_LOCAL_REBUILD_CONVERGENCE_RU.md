# C22 Incremental Local Rebuild — Production Convergence Candidate

**Дата:** 2026-08-10  
**Ветка:** `feature/c22-incremental-local-rebuild`  
**Base:** `main @ 0cb0416f20946afc85abe9abcded07bfcc493bf7`  
**PC0:** `PC0-2026-08-10-R1`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Статус:** `IMPLEMENTED_CANDIDATE_WINDOWS_FOCUSED_PENDING`

## Зачем создана отдельная ветка

TS0.3 доказал локальный dirty rebuild в evidence-ветке, но TS не должен владеть production `scripts/construction/proxies/**`.

Поэтому production перенос выполнен отдельно:

```text
feature/ts0-large-structural-visual-lab
        ↓ evidence
feature/c22-incremental-local-rebuild
        ↓ production convergence
main
```

TS lab code в convergence branch не переносится.

## Production fast path

```text
ConstructSnapshot N
        ↓ local mutation + dirty_part_ids
binary search dirty records in sorted snapshot
        ↓
old/new dirty section coordinates
        ↓
1-section rebuild neighborhood
        ↓
local occupancy with 1-section context halo
        ↓
rebuild only affected C22 section artifacts
        ↓
reuse unchanged content-addressed artifacts
        ↓
second-pass greedy merge → FAR root shell
        ↓
new manifest + invalidation plan
```

Fast path не делает полный обход `snapshot.parts` и не вызывает полный `Compiler.compile()`.

Unsupported случаи (`interior`, `interactive`, non-unit-grid, changed compile policy) автоматически используют прежний full-compile fallback.

## Focused correctness gate

Новый тест использует куб `32×32×32 = 32768` unit parts:

```text
total sections:        64
section size:           8 m
mutation:               remove 4×4×4 corner
removed/dirty parts:    64
base dirty sections:     1
rebuild sections:        8
reused sections:        56
context sections:       27
```

После incremental rebuild отдельно выполняется полный compile мутированного snapshot и требуется точное совпадение:

```text
topology checksum
section artifact IDs
root shell artifact ID
```

Таким образом gate проверяет одновременно locality и correctness.

## C24 prerequisite

`main` на момент создания ветки ещё содержал pre-fix winding contract. В convergence branch перенесён уже проверенный Godot-clockwise C24 winding fix, чтобы production graphical regression не возвращал ранее найденный back-face defect.

## Windows focused gate

```powershell
$Worktree = "C:\Godot\lunar-world-c22-incremental"
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

Set-Location $Worktree
.\RUN_C22_INCREMENTAL_REBUILD_TESTS.ps1 -GodotPath $Godot
```

Runner выполняет:

```text
editor import
C22 incremental local rebuild correctness
C22 compiled proxy graphical regression
C24 ArrayMesh backend contracts
```

## Full acceptance

Focused PASS недостаточен для merge.

После него на том же runtime head:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Только после full regression и PC0 audit ветка может быть объявлена merge-ready / SOURCE_ACCEPTED.
