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

Поэтому ожидаемый результат полного gate на текущем baseline — детерминированная остановка на `shared MW10 baseline`, до запуска project-level Godot runtime. Это корректный blocker, а не regression G6.

## Assistant-side Godot verification

Project upload содержит рабочую Linux double-сборку:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
binary: tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64
binary SHA-256: bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
archive SHA-256: d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

Движок реально запущен headless и выполнил GDScript smoke:

```text
GODOT_PROJECT_SMOKE: PASS
VECTOR3_SAMPLE: (0.12345678901234, 2.0, 3.0)
```

В assistant execution-container всё ещё нет полного checkout проекта, поэтому project-level G6 runtime gate здесь пока не запускался. Это ограничение checkout, а не Godot.

## После PASS

```text
G6.4 -> ACCEPTED
G6 Full -> ACCEPTED / SOURCE_ACCEPTED
next -> G7 Semantic Field Fabric
```

`MAIN_INTEGRATED`, `COMPOSITION_VERIFIED` и `PRODUCTION_READY` остаются отдельными статусами согласно GLOBAL-P0.
