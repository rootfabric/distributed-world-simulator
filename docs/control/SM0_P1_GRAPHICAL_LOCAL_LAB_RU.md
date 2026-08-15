# SM0-P1 — Graphical Local Handoff Lab

## Назначение

SM0-P1 добавляет ручную графическую проверку уже существующего SM0 two-authority handoff protocol. Это presentation/test surface, а не новый authority protocol и не новая canonical truth.

База P1: `bc108a441b98c84d9053266a8d4a33bdec1dc062` — H2.1, на которой подтверждены обычный 2/2 и Final 6/6 после реального `Stop-Process -Force` target authority и запуска нового процесса без смены player identity.

## Архитектурная граница

- authoritative position, session, ownership epoch, directory epoch и handoff остаются на существующих SM0 authority servers;
- `sm0_manual_client_node.gd` наследует прошедший H1/H2 `sm0_automated_client_node.gd` и меняет только источник movement delta с автоматического на ручной;
- graphical scene показывает derived projection authoritative player position;
- HUD показывает client-observed authoritative route state;
- серверный V2 handoff protocol не изменяется.

## Запуск на Windows

```powershell
cd C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab
.\RUN_V0_SM0_GRAPHICAL_LAB.ps1 -Restart
```

Runner использует только canonical double build:

```text
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe
4.7.1.stable.double.custom_build.a13da4feb
```

Управление:

- `A / D` — движение через authority boundary `x=0`;
- `W / S` — движение вдоль boundary;
- HUD показывает authority A/B, zone, client state, authority epoch, ownership epoch, player entity id, authoritative x/z и количество handoff;
- закрытие graphical Godot window завершает оба authority server process.

Чтобы потребовать минимум два реально наблюдавшихся crossing перед успешным завершением runner:

```powershell
.\RUN_V0_SM0_GRAPHICAL_LAB.ps1 -Restart -RequireHandoffs 2
```

Остановить stale session:

```powershell
.\RUN_V0_SM0_GRAPHICAL_LAB.ps1 -Stop
```

## Ожидаемая ручная проверка

1. После JOIN HUD показывает `Authority: A`, WEST и стабильный `player/a` identity.
2. Удерживать `D` до пересечения жёлтой линии `x=0`.
3. В переходе допустимы краткие `WAIT_HANDOFF` / `ACTIVATING`.
4. После завершения HUD показывает `Authority: B`, EAST, authority epoch увеличился, player entity id не изменился.
5. Удерживать `A` и пройти обратно; handoff counter должен увеличиться ещё раз.
6. Повторить несколько раз без телепорта identity, split ownership или зависшего frozen state.

## Не доказывает

P1 не заменяет H1 transport-fault acceptance и H2 crash/restart acceptance. Он также не доказывает crash after source retire / target commit; для этого требуется дальнейшая durable recovery semantics работа H2.2+.
