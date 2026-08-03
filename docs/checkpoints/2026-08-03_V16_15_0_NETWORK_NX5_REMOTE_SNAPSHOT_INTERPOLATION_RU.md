# Checkpoint v16.15.0 — NX5 Remote Snapshot Interpolation fix1

```text
checkpoint: v16.15.0-network-nx5-remote-snapshot-interpolation
build_id:   nx5-remote-snapshot-interpolation-fix1
branch:     feature/nx5-remote-snapshot-interpolation
base:       NX5 rejected candidate / 4efb873d1d0fc20e99f684fd3d4d0ba423423d7f
status:     FIX1 CANDIDATE FOR INDEPENDENT REVIEW
```

## Исправлено

- remote timeline теперь упорядочивает состояния по паре
  `(server_tick, outer snapshot_revision)`;
- новая revision внутри того же server tick заменяет authoritative sample,
  поэтому presentation delta для orientation и flashlight не теряется;
- изменённое состояние с той же самой парой clock по-прежнему отклоняется
  как `CONFLICTING_REMOTE_SNAPSHOT_TICK`;
- более старая same-tick revision отбрасывается нефатально и не может
  откатить position, orientation или flashlight;
- ошибка `apply_replica()` остаётся наблюдаемой в presenter report и журнале;
- возвращены 13 принятых assertions `transport-bound operation identity`;
- M3 manifest снова проверяется как `accepted`;
- M4 fixture восстановлен как полноценный canonical Item Graph snapshot;
- PowerShell и Linux runners больше не изменяют `HOME`/`USERPROFILE`,
  а временные environment variables восстанавливаются.

## Авторская проверка

```text
Godot:                    4.7.1 stable double a13da4feb
isolated editor import:   PASS
NX5 contracts:            6104 assertions, PASS
NX5 integration:            49 assertions, PASS
bash syntax:              PASS
JSON parse:               PASS
git diff --check:         PASS
```

M3/M4 managed graphical и полные NX4/Network/World regressions требуют
независимого запуска на полном рабочем дереве ветки.

## Обязательная приёмка

```powershell
.\RUN_NX5_REMOTE_SNAPSHOT_INTERPOLATION_TESTS.ps1 `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" `
  -IncludeGraphicalProcess `
  -IncludeAcceptedRegression
```

Checkpoint остаётся кандидатом до независимого прогона без failures.
