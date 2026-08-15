# V0-SM0 — первая исполняемая двухсерверная версия

## Статус

```text
branch: feature/sm0-two-authority-seamless-handoff-lab
product base: d66378b98b69756fab6c2a93b80b74db9ccd1980
status: FIRST NETWORK PROTOTYPE IMPLEMENTED / WINDOWS VERIFICATION REQUIRED
```

Это не acceptance checkpoint и не production seamless handoff.

Первая исполняемая версия предназначена для проверки базовой сетевой/authority-семантики до интеграции в graphical Earth/NX4 client.

## Что реализовано

```text
Dedicated Server A process
Dedicated Server B process
Automated Client process
```

Локальная topology:

```text
A gameplay :24580
B gameplay :24581
A control  :24680
B control  :24681
client UDP :24780 (stable for whole process)
```

Server A и B синхронизируют lab directory по отдельному localhost UDP control channel.

Client начинает на A, двигает canonical player state через реальные network packets, пересекает условную границу `x = 0`, получает handoff redirect, меняет active route на B и продолжает input sequence. Затем тот же процесс делает обратный переход B -> A.

## Authority protocol

```text
source movement reaches target zone
-> SOURCE_FROZEN
-> PLAYER_HANDOFF_PREPARE
-> TARGET SHADOW PREPARED
-> DIRECTORY_COMMITTED epoch N -> N+1
-> source leaves / loses writer state
-> target imports same player/a
-> client redirects same UDP endpoint
-> CLIENT_ACTIVATE
-> TARGET_ACTIVATED
-> source transfer tracking retires only after target commit ACK + client redirect ACK
```

Target PREPARE не создаёт active player.

Source после commit не становится writer снова.

Duplicate PREPARE и поздние ACK обрабатываются replay-safe в пределах первой localhost модели.

## Что переиспользуется

SM0 не создаёт второй gameplay store.

Player state идёт через существующий:

```text
MultiplayerGameplayAuthority
NetworkedGameplayService
```

Поэтому сохраняются существующие:

- `player/a` identity;
- join/leave ownership semantics;
- input sequence validation;
- movement state revision;
- existing player movement kernel/service.

## Что пока НЕ реализовано

Первая версия намеренно ещё не подключена к graphical `earth_mvp_app.gd` / M3 NX4 client router.

Поэтому локальный тест первой версии:

- headless;
- multi-process;
- real UDP network;
- real authority transfer;
- automatic A -> B -> A movement driver;
- structured log/evidence analysis.

Следующий bounded checkpoint после подтверждённого Windows PASS:

```text
SM0-T3 graphical Earth integration
```

Он должен заменить automated headless presentation на обычный Earth graphical client, не меняя уже доказанную authority state machine.

## Correctness first

Первый prototype не оценивается по плавности.

Допустимы freeze/presentation jump в будущей graphical интеграции. Сейчас hard gate:

```text
same logical_player_id
same player_entity_id
one active writer semantics
monotonic directory authority epoch
continuous client input sequence
source fenced after commit
target inactive before commit
A/B directory convergence
same client process across all crossings
no unexpected ERROR / invariant violation
```

## Windows verification command

Canonical layout:

```text
C:\distributed-world-simulator\distributed-world-simulator\
C:\distributed-world-simulator\worktrees\...
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
```

Developer gate:

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Handoffs 4 -Restart
```

Final stress of this prototype:

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Final -Restart
```

`-Final` = 20 authority handoffs.

Evidence is written under:

```text
%LOCALAPPDATA%\DistributedWorldSimulator\SM0Seamless\logs\<session-id>\
```

Expected files:

```text
contracts.log
server-a.log
server-b.log
client.log
client-result.json
harness.log
control.jsonl
handoffs.jsonl
summary.json
```

Windows runtime PASS is required before this prototype may be classified as verified.
