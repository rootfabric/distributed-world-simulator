# G6 Full Acceptance — FIX2 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

G6.0–G6.4 приняты. Shared MW10 baseline интегрирован в G5 и синхронизирован в G6.

## Первый full-gate

Windows full-gate прошёл G6.0–G6.4 и MW10 retry `12/12`, но общий world regression coverage guard обнаружил, что новый тест существует в проекте, но отсутствует в `$Tests` списка `RUN_WORLD_REGRESSION_TESTS.ps1`.

Fix1 был внесён в shared G5 baseline и синхронизирован в G6:

```text
69cfaf9171127df7af563b5f9af6812d7775b74d
+ res://tests/matter/transactions/test_mw10_lock_release_retry.gd
```

## Второй full-gate preflight

После обновления checkout Godot создал новый untracked sidecar:

```text
?? tests/matter/transactions/test_mw10_lock_release_retry.gd.uid
```

Поэтому clean-tree preflight корректно остановил acceptance до запуска runtime.

Это shared G5 hygiene/integration defect, а не G6 runtime regression.

## Fix2

UID сгенерирован project-provided Godot 4.7.1 double через `ResourceUID.create_id()` и `ResourceUID.id_to_text()`:

```text
uid://yush8dg03nlf
```

Он добавлен в G5 как tracked file:

```text
tests/matter/transactions/test_mw10_lock_release_retry.gd.uid
```

После lineage-sync G5→G6 свежий `git reset --hard origin/feature/g6-hydrology-fluid-surface-v0` должен заменить локальный untracked sidecar tracked-версией и вернуть clean checkout.

## Финальный gate

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Требуется:

```text
clean repository preflight             PASS
GLOBAL / G5 ancestry                    PASS
shared MW10 blobs                       PASS
git diff --check G5...G6               PASS
G6.0-G6.4                               PASS
MW10 retry                              PASS
world regression manifest coverage      PASS
RUN_WORLD_REGRESSION_TESTS.ps1          PASS
final repository hygiene                PASS
G6 FULL ACCEPTANCE                      PASS
```

Только после этого фиксируется `G6 SOURCE_ACCEPTED`, затем начинается G7 Semantic Field Fabric.
