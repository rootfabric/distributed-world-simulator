# T1A.0 fix1 — Regression Hygiene / Persistence Isolation

**Дата:** 2026-08-08  
**Ветка:** `feature/t1-complex-construct-demo-lab`  
**Статус:** `FIX1 IMPLEMENTED CANDIDATE`  
**Baseline head до fix1:** `f08c3401bd9fbd970c317f4d24a240a39668ee04`  
**Fix1 implementation head:** `197a4d1ba0c92ace0f7eb5c658a621ae15faaedf`

## Причина fix1

Полный Windows/Godot 4.7.1 double regression формально завершился `PASS`, но в stdout/stderr присутствовали реальные runtime diagnostics:

- обычные boot-сценарии `test_world_switch_during_generation` и `test_world_boot_matrix` получали `World manifest identity mismatch (partition_scheme_revision, partition_grid)` и продолжали выполнение после `repository_setup_failed`;
- multi-process Matter/Representation tests многократно получали `breakpoint_runtime could not listen on 127.0.0.1:9081`;
- после MW7 присутствовали `ObjectDB instances were leaked at exit` / `resources still in use at exit` diagnostics;
- общий PowerShell runner считал шаг успешным по exit code / explicit FAIL markers и поэтому мог показать зелёный итог при обычном runtime `ERROR:`.

Негативные persistence/NX5/NX6 сценарии, которые специально проверяют reject paths, остаются допустимыми. Fix1 направлен только на unexpected diagnostics обычного boot/acceptance path.

## Root cause

### Shared `user://` между независимыми test processes

`RUN_WORLD_REGRESSION_TESTS.ps1` создавал один isolated profile на весь regression run. Все самостоятельные Godot test scripts использовали один `user://`.

Из-за этого manifest, созданный или изменённый предыдущим standalone process, мог влиять на последующий boot-test. Для standalone regression это скрытая межтестовая зависимость.

### MCP runtime bridge в headless regression

`BreakpointRuntimeBridge` является project autoload и по умолчанию слушает `127.0.0.1:9081`. Multi-process suites создают несколько Godot processes, поэтому debug bridge конкурировал за один loopback port. Это не является частью gameplay/network acceptance.

### Boot tests не проверяли persistence health

`LunarApp` логирует `repository_setup_failed`, но runtime продолжает подниматься. Старые boot tests проверяли world/runtime/commands, но не `persistence.initialized`, поэтому такой startup мог закончиться `PASS`.

## Реализованный fix

### 1. Per-step user profile isolation

`RUN_WORLD_REGRESSION_TESTS.ps1` теперь создаёт отдельный child profile для каждого `Invoke-GodotStep`:

```text
artifacts/test-results/world-profile-<runner-pid>/
  steps/
    002-editor_import_parse/
    003-test_double_precision_contract/
    ...
    NNN-test_world_boot_matrix/
```

Для каждого шага отдельно выставляются:

- `APPDATA`
- `LOCALAPPDATA`
- `USERPROFILE`
- `HOME`
- `XDG_DATA_HOME`
- `XDG_CONFIG_HOME`
- `XDG_CACHE_HOME`

После завершения процесса environment восстанавливается.

Дочерние Godot processes, которые создаёт один multi-process test, наследуют профиль своего родительского шага. Поэтому внутренние restart/reconnect/durable-recovery сценарии сохраняют совместное test state, но разные standalone tests больше не загрязняют друг друга.

### 2. Breakpoint runtime bridge disabled for regression

Runner выставляет:

```text
BREAKPOINT_RUNTIME_DISABLED=1
```

То же сделано в focused runners:

- `RUN_T1A0_COMPLEX_CONSTRUCT_DEMO_TESTS.ps1`;
- `RUN_T1A0_COMPLEX_CONSTRUCT_DEMO_TESTS.sh`.

Debug/MCP bridge не входит в headless acceptance semantics и не должен создавать port/resource diagnostics в этих тестах.

### 3. Persistence health is now an explicit boot contract

Добавлены fail-closed assertions:

- `tests/integration/test_unified_runtime_boot.gd`
- `tests/runtime/test_world_switch_during_generation.gd`
- `tests/runtime/test_world_boot_matrix.gd`

Для Moon / Earth+Moon runtime теперь обязательно:

```text
runtime.persistence != null
runtime.persistence.initialized == true
```

Если `repository_setup_failed` повторится, boot test больше не сможет закончиться зелёным только потому, что остальная сцена продолжила запуск.

### 4. Runtime error hygiene gate

PowerShell runner отдельно помечает как failure любой обычный `ERROR:` в шагах:

- `test_unified_runtime_boot`
- `test_world_switch_during_generation`
- `test_world_boot_matrix`
- `main_scene_cli_all`

Это намеренно не применяется глобально ко всем negative-path suites, где `push_error()` является частью тестируемого reject behavior.

Кроме того, следующие diagnostics являются глобальным hard failure независимо от suite:

```text
ERROR: [breakpoint_runtime] could not listen ...
WARNING: <N> ObjectDB instances were leaked at exit
ERROR: <N> resources still in use at exit
```

Поэтому повторение MW7 leak или MCP port collision теперь физически не может закончиться общим зелёным regression result.

## Fix1 commits

```text
ac8a1306a985350a3062d4c413f19c86d7da2dd7  test(t1a0): isolate regression runtime state
e353e1bb4f1da065cf5b64fc42083eb064deef3f  test(t1a0): require healthy persistence on world switch
5c0c094de829c20994b04dbe440077381a938848  test(t1a0): gate boot matrix on persistence health
02fd8eab38c3f3ed3c49a497de34b386157df082  test(t1a0): gate unified boot on persistence health
f41c3c67cafb6ef985ce46a6dd9640ff8be03f40  test(t1a0): disable runtime bridge in headless acceptance
aa7488c439571669399cb7dbc9b150a6751770c9  test(t1a0): minimize boot matrix persistence diff
dbc118ad7272ff2419108c629d5d6d825af435c8  test(t1a0): disable runtime bridge in shell acceptance
197a4d1ba0c92ace0f7eb5c658a621ae15faaedf  test(t1a0): fail regression on bridge and leak diagnostics
```

Metadata/validation commits that follow the implementation head do not change runtime behavior.

## Что должно исчезнуть после rerun

В обычных boot tests не должно быть:

```text
World manifest identity mismatch
repository_start_aborted
repository_setup_failed
```

В MW9/MW10/RL3 multi-process output не должно быть:

```text
[breakpoint_runtime] could not listen on 127.0.0.1:9081
```

Если после отключения runtime bridge MW7 всё ещё выдаст `ObjectDB instances were leaked at exit` / `resources still in use at exit`, полный runner теперь остановится на MW7. Это будет отдельный реальный ownership/cleanup defect, а не скрытый warning в успешном прогоне.

## Проверка

Focused:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_T1A0_COMPLEX_CONSTRUCT_DEMO_TESTS.ps1 -GodotPath $Godot
```

Full regression:

```powershell
$env:GODOT_BIN = $Godot
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Для проверки сохранённых текстовых логов, если они есть в `artifacts`, используйте:

```powershell
Get-ChildItem .\artifacts -Recurse -File |
  Select-String -Pattern "World manifest identity mismatch|repository_setup_failed|breakpoint_runtime|ObjectDB instances were leaked|resources still in use"
```

Главным источником истины остаётся stdout полного runner: intentional negative-path persistence errors допустимы только внутри соответствующих focused tests, а normal boot paths и engine leak diagnostics теперь fail-closed.

## Acceptance fix1

Fix1 можно принять только если:

1. T1A.0 focused runner PASS;
2. full regression PASS;
3. normal boot persistence health PASS;
4. `World manifest identity mismatch` отсутствует вне намеренных persistence negative tests;
5. `breakpoint_runtime ... 9081` отсутствует;
6. MW7 exit leak diagnostics отсутствуют;
7. production Item/Construction contracts не изменены.

## Решение

```text
checkpoint: T1A0_REGRESSION_HYGIENE_FIX1
decision:   FIX1_IMPLEMENTED_CANDIDATE
next:       LOCAL_WINDOWS_GODOT_RERUN
```
