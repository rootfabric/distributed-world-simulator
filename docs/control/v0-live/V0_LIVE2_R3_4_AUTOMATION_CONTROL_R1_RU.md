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