# Checkpoint v16.6.0 — Network N2 process harness

**Статус:** candidate для независимой Windows-проверки
**Build ID:** `n2-cross-platform-process-orchestration`
**Ветка:** `feature/n2-process-harness`
**База:** `v16.5.2-foundation-network-n1`

## Результат

N2 завершает ручное разрозненное выполнение N1 process fixtures и вводит один кроссплатформенный manifest-driven harness.

Реализованы:

- динамические UDP-порты;
- изолированные server/client `user://`;
- readiness, terminal и shutdown timeouts;
- stdout/stderr capture;
- строгая проверка terminal report и process exit code;
- success и expected-failure сценарии;
- обязательная cleanup-ветка;
- JSON и JUnit отчёты;
- фильтрация одного сценария;
- строгая validation manifest.

## Сценарии

```text
n1_snapshot_success
n1_remote_item_success
n1_reconnect_replay_success
readiness_timeout_cleanup
client_failure_cleanup
nonzero_exit_after_terminal
```

## Дополнительное hardening

Закрыты:

- scenario/node path traversal;
- reserved argument override;
- malformed field paths;
- missing scripts;
- fractional/unsafe timeout values;
- ложный PASS при ненулевом process exit;
- потеря фактического failure-кода;
- readiness race в nonzero-exit probe;
- ложный PASS PowerShell/Bash runners при текстовом `FAIL` и нулевом exit code Godot;
- Windows `NativeCommandError` на ожидаемом Godot stderr при `$ErrorActionPreference = "Stop"`;
- чтение частично записанного JSON report; terminal reports и N2 summary теперь публикуются атомарно, PowerShell reader использует retry;
- нулевой `world-regression-summary.json` после прямого `Set-Content`: world runner публикует summary через проверенный временный файл, durable flush и атомарную замену с восстановлением предыдущей версии при ошибке.

## Локальная Linux-проверка перед поставкой

```text
Editor import/parse:             PASS
N2 contracts:                    95/95
N2 process assertions:           76/76
Direct harness stability:        5/5 запусков, 6/6 scenarios
Network profile:                 21/21 suites, 1917/1917 assertions
Main scene:                      6 PASS, 0 FAIL
Simulation-server lifecycle:     PASS
Terrain drain:                   4196 мс
```

Полный world regression является обязательным acceptance gate на пользовательской Windows double-сборке.

## Следующий этап

```text
R3.1 — authoritative persistence and crash recovery
branch: feature/r3.1-authoritative-recovery
checkpoint: v16.7.0-repository-r3.1-authoritative-recovery
```
