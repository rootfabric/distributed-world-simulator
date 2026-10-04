# LIVE.2 R3.4 — автономное управление GUI-клиентом

## Цель

Дать тестовому агенту возможность самостоятельно запускать и управлять реальными LIVE.2 GUI-клиентами без SendKeys, AutoHotkey, pyautogui и ручного участия человека.

Обычный игровой режим не меняется. Контур включается только явным debug-флагом.

## Архитектура

Клиент при явном запуске automation control поднимает локальный TCP JSONL endpoint:

- bind: только `127.0.0.1`;
- отдельный port для каждого GUI-клиента;
- обязательный token;
- требуется `--network-debug`;
- только role `game-client`;
- по умолчанию полностью выключено.

Внешний агент может использовать `tools/live2/live2_automation_client.py`, свой TCP-клиент или MCP adapter поверх этого API. MCP не является gameplay/runtime authority.

## Launch

```text
--automation-control
--automation-control-port=27651
--automation-control-token=<random-token>
--automation-control-output-dir=<session>/automation-a
```

Client B использует другой port, например 27652. Без `--automation-control` TCPServer не создаётся.

## Protocol

Request:

```json
{
  "schema": "dws.live2.automation.request.v1",
  "id": "request-1",
  "token": "...",
  "method": "command.execute",
  "params": {"line": "player.interact"}
}
```

Один JSON object на строку. Response использует schema `dws.live2.automation.response.v1`.

## Methods

- `ping` — bridge/world identity;
- `commands.list` — структурированный Command Registry;
- `command.execute` — существующие gameplay/UI/network commands;
- `movement.set` — временный NX4 movement intent с TTL;
- `movement.stop` — neutral input;
- `view.set` — Earth-relative yaw/pitch;
- `input.key` — bounded Godot InputEventKey injection;
- `input.pointer_move` / `input.pointer_button` — реальные Godot UI pointer events;
- `state.get` — runtime/jitter/automation state;
- `screenshot.capture` — PNG viewport в заданный evidence directory.

`movement.set` не создаёт второй authority path: intent проходит через существующие prediction → network input → authoritative server seams. TTL 100..10000 ms не позволяет персонажу продолжать движение после смерти controller-процесса.

## CLI examples

```powershell
python tools/live2/live2_automation_client.py --port 27651 --token $Token ping
python tools/live2/live2_automation_client.py --port 27651 --token $Token move --z=-1 --sprint --yaw 0 --ttl-ms 1000
python tools/live2/live2_automation_client.py --port 27651 --token $Token stop
python tools/live2/live2_automation_client.py --port 27651 --token $Token command "player.interact"
python tools/live2/live2_automation_client.py --port 27651 --token $Token state --kind jitter
python tools/live2/live2_automation_client.py --port 27651 --token $Token screenshot --filename a-after-move.png
```

Для UI agent может отдельно отправлять Tab/Esc/G и pointer move/button, поэтому сценарии drag + key тоже можно воспроизводить без OS input injection.

## Почему не встраивать сторонний Godot MCP

Godot MCP удобен как tooling adapter, но не должен становиться runtime dependency продукта. Наш bridge versioned вместе с LIVE2, использует существующие gameplay seams, не разрешает arbitrary GDScript eval/node mutation, слушает только loopback и по умолчанию выключен.

Позже MCP server может просто отобразить tools `live2_ping`, `live2_command`, `live2_move`, `live2_view`, `live2_key`, `live2_pointer`, `live2_state`, `live2_screenshot` на этот API.

## Autonomous two-client test

Агент может без человека: запустить server; A:27651 и B:27652; дождаться CONNECTED; двигать обоих; смотреть state/screenshots; выполнять pickup/mining/place/construction; воспроизводить Tab/Esc/G и drag; делать reconnect; проверять convergence; завершать клиентов и собирать evidence.

## Non-goals

R3.4 не меняет network protocol, transport modes, prediction/reconciliation, interpolation coefficients и canonical ownership. Это только test/control surface.
## Готовый автономный A/B playtest runner

Для воспроизводимого smoke/lag измерения добавлен:

`tools/live2/run_live2_autonomous_playtest.ps1`

Он самостоятельно:

1. проверяет, что нет чужих Godot-процессов;
2. создаёт отдельные APPDATA/LOCALAPPDATA профили;
3. запускает dedicated server;
4. запускает GUI client A и B с разными automation ports;
5. ждёт `ping` и `connection_state=CONNECTED`;
6. делает baseline screenshots и jitter snapshots;
7. двигает A при неподвижном B, затем B при неподвижном A;
8. выполняет дополнительные zig-zag movement phases;
9. пробует interact/equip/hotbar/build/place/construction;
10. воспроизводит Tab/G/Esc через Godot InputEvent;
11. делает reconnect и post-reconnect movement;
12. собирает `automation-actions.jsonl`, `jitter-samples.jsonl`, PNG и client/server logs;
13. вызывает `movement.stop`, `app.quit` и завершает оставшиеся процессы;
14. пишет `AUTONOMOUS-PLAYTEST-REPORT.json`.

Пример:

```powershell
pwsh tools/live2/run_live2_autonomous_playtest.ps1 `
  -Worktree C:\distributed-world-simulator\live2-auto\wt `
  -MovementPhaseSeconds 20
```

Runner предназначен для базового полностью автономного прогона. Агент может после него анализировать JSON/PNG, а затем использовать `live2_automation_client.py` адаптивно для дополнительных сценариев: приблизиться к конкретному объекту, повторить UI drag, сделать дополнительные screenshot/state probes и т.п.

### Метрики лагов

Основной машинный evidence хранится в `jitter-samples.jsonl`. Для каждого клиента сохраняется результат `network.jitter.snapshot`, включая local reconciliation и remote presenter/interpolation telemetry.

При анализе сравнивать:

- `local.maximum_error_m`, `hard_corrections`, `history_miss_resets`, `ticks_replayed`;
- `snapshot_clock_context` и `snapshot_clock_source`;
- `presenter_arrivals` и `accepted_presenter_samples`;
- `max_presenter_arrival_interval_ms` и `max_accepted_sample_interval_ms`;
- `sample_mode_time_ms` вместо сырых frame counters;
- `long_render_frames` и `max_render_delta_ms`;
- A-sees-B против B-sees-A;
- состояние до/после gameplay actions и reconnect.

Важно: rejected gameplay command не считается failure автономного harness. Он сохраняется как product observation. Harness FAIL — это потеря control bridge, process crash, невозможность подключить клиентов или нарушение самого automation protocol.
## Автоматический анализ лагов

После playtest runner автоматически запускает `tools/live2/analyze_live2_autonomous_playtest.py`.

Он создаёт:

- `AUTONOMOUS-LAG-ANALYSIS.json` — структурированный машинный отчёт;
- `AUTONOMOUS-LAG-ANALYSIS.md` — краткую читаемую сводку;
- `analysis-console.txt` — консольный summary.

Analyzer считает дельты по movement-фазам, а не сравнивает абсолютные lifetime counters. Он отдельно показывает:

- local hard corrections/history-miss/ticks-replayed;
- remote INTERPOLATE/EXTRAPOLATE/HOLD time ratios;
- presenter arrivals против accepted presenter samples;
- max presenter-arrival и accepted-sample gaps;
- render stalls;
- snapshot clock source;
- watchdog/physical mismatch/input queue/async rejection counts.

Пороговые finding-и диагностические, не заменяют product acceptance. Сырой JSONL и логи всегда сохраняются рядом.