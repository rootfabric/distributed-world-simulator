# G6 Full Acceptance — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09  
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

G6.4 Fix4 получил ручной graphical PASS: при приближении наблюдается refine сетки до LOD 10 и появляются дополнительные высокочастотные неровности diagnostic G3 surface. Остался автоматический Fix4 rerun, который теперь встроен в полный G6 gate.

## Новый gate

Windows entrypoint:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

Он выполняет:

```text
clean worktree
  ↓
GLOBAL config == main == G5
  ↓
current G5 is ancestor of G6
  ↓
accepted MW10 atomic-lock blobs exist in G5
  ↓
same blobs exist in resynchronized G6
  ↓
git diff --check G5...G6
  ↓
G6.4 Fix4 automated gate
  └─ G5 graph / feature-cell
  └─ G6.0 contracts
  └─ G6.1 provider
  └─ G6.2 continuity
  └─ G6.3 runtime query
  └─ G6.4 adaptive representation
  ↓
MW10 lock-release retry fault injection
  ↓
RUN_WORLD_REGRESSION_TESTS.ps1
  ↓
final clean worktree + diff check
```

## Текущий блокер

PR #43 `MW10: integrate atomic lock release into shared G5 baseline` на момент создания checkpoint открыт и не влит.

Требуемые принятые blobs:

```text
matter_cross_region_transaction_repository.gd
a25b7d8c358410e60e1bb7db9d3f99333a305a63

test_mw10_lock_release_retry.gd
afab0c98de45c34dcf6c923d622c84835d428fa5
```

По архитектурной политике мы **не копируем этот fix приватно в G6**. Сначала он должен стать частью G5 shared baseline, после чего G6 синхронизируется поверх обновлённого G5.

Поэтому ожидаемый результат полного gate на текущем baseline — детерминированная остановка на `shared MW10 baseline`, до запуска Godot runtime. Это корректный blocker, а не regression G6.

## Самостоятельный runtime test из assistant environment

Попытка выполнена, но в доступном runtime нет локального checkout проекта и нет Godot binary; сетевой clone/download из container также недоступен. Поэтому assistant-side Godot PASS не заявляется. Финальное runtime evidence должно быть получено на Windows Godot 4.7.1 double после shared-baseline resync.

## После PASS

```text
G6.4 -> ACCEPTED
G6 Full -> ACCEPTED / SOURCE_ACCEPTED
next -> G7 Semantic Field Fabric
```

`MAIN_INTEGRATED`, `COMPOSITION_VERIFIED` и `PRODUCTION_READY` остаются отдельными статусами согласно GLOBAL-P0.
