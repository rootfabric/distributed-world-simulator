# N2 — multi-process network harness

## Назначение

N2 объединяет process-level проверки N1.1–N1.3 в один manifest-driven orchestration layer. Harness запускает реальные отдельные Godot-процессы, а не вызывает server/client sessions внутри одного `SceneTree`.

Основной manifest:

```text
config/testing/network-process-scenarios.v1.json
```

Реализация:

```text
scripts/testing/process_harness/process_harness_manifest.gd
scripts/testing/process_harness/network_process_harness.gd
scripts/testing/process_harness/junit_report_writer.gd
scripts/testing/process_harness/atomic_json_file.gd
tools/testing/n2_process_harness_runner.gd
```

## Гарантии

Для каждого сценария harness создаёт:

- динамический свободный UDP-порт;
- отдельный каталог запуска;
- отдельный `user://` для server и client;
- отдельные stdout/stderr logs;
- JSON terminal reports с атомарной заменой файла;
- readiness и scenario timeout;
- cleanup дочерних процессов;
- machine-readable result;
- устойчивое чтение ещё не завершённого report без engine `ERROR`.

Manifest запрещает:

- path traversal в scenario/node identifiers;
- отсутствующие `res://` scripts;
- дополнительные поля;
- дробные или unsafe integers в timeout/port settings;
- неканонические field paths;
- runtime objects;
- переопределение зарезервированных аргументов `host`, `port`, `node-id`, `result-file`, `timeout-ms`.

## Сценарии

```text
n1_snapshot_success
n1_remote_item_success
n1_reconnect_replay_success
readiness_timeout_cleanup
client_failure_cleanup
nonzero_exit_after_terminal
```

Последние три сценария являются ожидаемыми отказами. Они проходят только при точном совпадении `observed_failure_code` и отсутствии живых server/client процессов после cleanup.

## Отчёты

По умолчанию создаются:

```text
artifacts/test-results/n2-process-harness-summary.json
artifacts/test-results/n2-process-harness-junit.xml
artifacts/test-results/n2-process-runs/
```

## Запуск Windows

```powershell
.\RUN_N2_PROCESS_HARNESS_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Один сценарий:

```powershell
.\RUN_N2_PROCESS_HARNESS_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" `
  -Scenario "n1_reconnect_replay_success"
```

## Запуск Linux

```bash
GODOT_BIN=/path/to/godot.linuxbsd.editor.double.x86_64 \
  ./RUN_N2_PROCESS_HARNESS_TESTS.sh
```


## Windows runner safety

PowerShell runners сохраняют глобальный `$ErrorActionPreference = "Stop"`, но на время запуска Godot локально переводят обработку native stderr в диагностический режим. Поэтому ожидаемые `ERROR:` из fail-closed тестов остаются в логе, но не превращаются в terminating `NativeCommandError`. Exit code Godot и текстовый маркер `: FAIL` по-прежнему проверяются отдельно.

`RUN_N2_PROCESS_HARNESS_TESTS.ps1` читает итоговый JSON через retry-loop. Пустой, отсутствующий или временно неполный файл повторно проверяется до timeout, а не приводит к случайному `ConvertFrom-Json` failure.

`RUN_WORLD_REGRESSION_TESTS.ps1` также публикует `world-regression-summary.json` атомарно: временный файл записывается в том же каталоге, принудительно flush'ится, повторно валидируется через `ConvertFrom-Json`, после чего заменяет конечный файл через `File.Replace` или `File.Move`. Прерывание записи больше не может оставить итоговый summary нулевым или частичным.

## Acceptance

```text
contracts PASS
process tests PASS
6/6 scenarios PASS
JSON passed=true
JUnit failures=0
unique dynamic ports
separate server/client user roots
server_running_after_cleanup=false
client_running_after_cleanup=false
```
