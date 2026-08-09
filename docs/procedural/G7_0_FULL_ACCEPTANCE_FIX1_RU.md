# G7.0 Full Acceptance — Fix1 Windows focused PASS

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g7-semantic-field-fabric`

Первый полный Windows gate G7.0 прошёл focused semantic-field contracts и дошёл до общего world/core regression. Единственный blocker проявился в `test_m4_graphical_shared_gameplay_processes.gd`.

```text
A/B graphical                         PASS
A pickup                              PASS
B contention rejection               PASS
foreign inventory permission          PASS
A/B Item Graph checksum convergence   PASS
server report Item Graph assertions   FAIL (4)
```

## Root cause

Диагностика показала race чтения `server.json` во время AtomicJson replacement. Dedicated server при записи verified report временно переименовывает текущий target в backup, затем ставит новый target. M4 process-test после завершения клиентов выполнял один обычный `FileAccess` read одновременно с disconnect/report write.

При попадании в короткое Windows-окно `_read()` возвращал `{}`, поэтому одновременно падали проверки:

```text
server canonical graph has one beacon
beacon replicated in shared container
server item graph checksum
server and clients item graph checksum convergence
```

При этом A и B уже имели одинаковый canonical Item Graph checksum, что отделило report-read race от gameplay divergence.

## Shared G6 fix

Fix реализован в upstream `feature/g6-hydrology-fluid-surface-v0`:

```text
G6 head: 62def33a40481354820adfb6288672183887c9f1

tests/runtime/test_m4_graphical_shared_gameplay_processes.gd
  blob: 9a17996df2545efbaaa807283b9ec70542e35128

validation/g6-post-acceptance-m4-report-race-fix1.json
docs/checkpoints/G6_POST_ACCEPTANCE_M4_REPORT_RACE_FIX1_RU.md
```

M4 теперь ждёт валидный server Item Graph report до 10 секунд. Он не маскирует реальный mismatch: при timeout возвращается последний валидный server snapshot и прежняя checksum-convergence assertion остаётся authoritative.

Production runtime, Item Graph semantics и network protocol не менялись.

## Assistant exact-engine smoke

На project-provided Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
M4_REPORT_RACE_SMOKE: PASS
```

Smoke воспроизвёл последовательность:

```text
stale valid report
    -> target temporarily missing
    -> final valid report
```

и новый wait-contract корректно дождался final checksum.

## G7 synchronization

Current G6 синхронизирован в G7 merge-коммитом:

```text
0c08c600c10bfedd730243e866bfa272aa14707b
```

После синхронизации `feature/g7-semantic-field-fabric` имеет current G6 как ancestor и `behind_by = 0`.

## Windows focused verification

На checkout head `31316df5dc1068888a1e411d14c8af733a68ebc1` выполнен прямой Windows Godot run:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
M4 graphical shared gameplay: 22 assertions, 0 failures
```

Подтверждены:

```text
server canonical graph has one beacon          PASS
beacon replicated in shared container          PASS
server item graph checksum                     PASS
A received item graph replica                  PASS
B received item graph replica                  PASS
A/B checksum convergence                       PASS
server/client checksum convergence             PASS
A clean shutdown                               PASS
B clean shutdown                               PASS
```

После удаления transient `Microsoft/`:

```text
git status --porcelain   EMPTY
```

Таким образом Fix1 считается подтверждённым на Windows focused gate. G7.0 целиком пока не принят: требуется только повторный полный `RUN_G7_0_FULL_ACCEPTANCE.ps1`.

## Следующий gate

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_0_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Ожидаемый финальный marker:

```text
G7.0 FULL ACCEPTANCE: PASS
World/core regression: PASS
Working tree: CLEAN
```
