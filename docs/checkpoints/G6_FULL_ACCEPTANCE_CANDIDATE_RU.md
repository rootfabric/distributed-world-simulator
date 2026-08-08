# G6 Full Acceptance — READY FOR FULL WINDOWS GATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

Все внутренние checkpoint G6.0–G6.4 приняты. Shared MW10 blocker, ранее найденный full-gate, устранён через общий G5 baseline, а не приватную копию в G6.

## Shared G5 baseline

PR #43 интегрирован в `feature/g5-world-feature-graph`.

Текущий принятый G5 shared-baseline head:

```text
6e83824956f4bb9337ba0e22be6c40ccfca8bd43
```

Accepted MW10 blobs:

```text
matter_cross_region_transaction_repository.gd
a25b7d8c358410e60e1bb7db9d3f99333a305a63

test_mw10_lock_release_retry.gd
afab0c98de45c34dcf6c923d622c84835d428fa5
```

G6 синхронизирован lineage-preserving merges:

```text
PR #47 runtime sync     d5879f7a5263ad98eb8ae575194e34d69a74e56c
PR #48 metadata sync    854d79cbde7daf4ce72d2b89dd3d8900401fbcd0
```

Current G5 является реальным ancestor G6; compare показывает `behind G5 = 0`.

## Assistant-side Linux double verification

Использован project-provided:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
linuxbsd-x86_64-double
```

После интеграции повторно пройдены focused checks:

```text
MW10 lock release retry          PASS — 12 assertions
MW10 acquire/release stress      PASS — 501 assertions / 100 cycles
G6 production contract smoke     PASS — 115 assertions
```

G6 focused smoke исполняет exact current production `FluidType`, `FluidRegionId` и `WaterSurfaceQuery`; generic hashing/spatial dependencies изолированы, поэтому этот smoke является дополнительным evidence, но не заменяет full-tree regression.

## Full runner correction

После принятия G6.4 обнаружен stale orchestration contract: full-runner всё ещё ожидал промежуточный status `FIX4_MANUAL_PASS_AUTOMATED_RERUN_REQUIRED`.

Исправлено:

```text
RUN_G6_FULL_ACCEPTANCE.ps1  183c96a8541a177606a31a74ea83bd86a4a3fad2
RUN_G6_FULL_ACCEPTANCE.sh   96cdb7f672b802852a4388508edb99ea884977f5
```

Теперь full gate требует окончательный `G6.4 decision = ACCEPTED`.

## Финальный Windows gate

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

Gate выполняет:

```text
clean worktree
  ↓
GLOBAL config == main == G5
  ↓
current G5 is ancestor of G6
  ↓
exact accepted MW10 blobs in G5 and G6
  ↓
git diff --check G5...G6
  ↓
accepted G6.0-G6.4 focused chain rerun
  ↓
MW10 lock-release retry fault injection
  ↓
RUN_WORLD_REGRESSION_TESTS.ps1
  ↓
final clean worktree + diff check
```

## Статус

```text
G6.0-G6.4            ACCEPTED
G5 + MW10 baseline   ACCEPTED
G6 resync             PASS
assistant focused     PASS
full world regression PENDING WINDOWS FULL TREE
G6 Full               READY FOR FULL WINDOWS GATE
```

`G6 SOURCE_ACCEPTED` фиксируется только после полного зелёного `RUN_G6_FULL_ACCEPTANCE.ps1`. После этого следующий procedural checkpoint — `G7 Semantic Field Fabric`.

`MAIN_INTEGRATED`, `COMPOSITION_VERIFIED` и `PRODUCTION_READY` остаются отдельными статусами согласно GLOBAL-P0.
