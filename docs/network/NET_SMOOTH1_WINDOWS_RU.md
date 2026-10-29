# NET-SMOOTH1 R1 — инструкции Windows-агенту

## Статус и субъект

Ветка: `repair/net-smooth1-char2-r1`, exact parent
`f861de654b5cc6aa281f150259bf55d4a42f042b` (CHAR2). Main и PR #748 не изменять.
План: `docs/network/NET_SMOOTH1_PLAN_RU.md`. Это implementer candidate, не VERIFIED.

Изменения R1: bounded HOLD без обратного скачка; корректная классификация
sequence-ID skips; один асинхронный periodic checkpoint writer; main-thread
capture и sync command barriers сохранены; bounded process-local JSONL tracing;
автоматическое движение настоящих Earth-клиентов; staged portable launcher.

Непокрытые обязательства: ограничение replay-истории с сохранением dedup,
неблокирующий durable command path, устранение стоимости main-thread capture,
активная зеркальность yaw, полный crash-in-write fault matrix, WAN quality
criteria, длительная GUI-приёмка. R1 не объявляет эти пункты исправленными.

## Импорт переданного Git-bundle

Использовать `IMPORT_NET_SMOOTH1.ps1` из delivery ZIP. Он проверяет prerequisite
CHAR2, SHA ветки, создаёт новый worktree; `-Push` делает только обычный non-force
push repair-ветки и сравнивает remote SHA. При конфликте ветки/каталога остановиться;
никаких reset/force/merge. Git-bundle содержит реальные коммиты поверх исходного
CHAR2, не synthetic root и не архив неподтверждённых изменений.

Стандартный layout:

```powershell
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$WT = 'C:\distributed-world-simulator\worktrees\net-smooth1-char2-r1'
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
```

Все следующие команды выполняются из нового `$WT`. Python 3.10+ должен быть
доступен как `python`. Использовать canonical Godot 4.7.1 double, не single.
Проверить `git rev-parse HEAD`, `git rev-parse 'HEAD^{tree}'`, версию и SHA256 Godot.
Не запускать одновременно с другим нагрузочным тестом. Не завершать вручную
запущенную пользовательскую игру: стенд использует свои порты и каталоги.

## 1. Тесты контрактов и процессов

```powershell
Set-Location $WT
python -m unittest discover -s tests/tools -p test_net_smooth1_analyzer.py -v
if ($LASTEXITCODE -ne 0) { throw 'ANALYZER_SELF_TEST_FAILED' }
.\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests `
    -OutputDirectory "$WT\artifacts\net-smooth1\windows-focused"
if ($LASTEXITCODE -ne 0) { throw 'FOCUSED_OR_PROCESS_GATE_FAILED' }
```

Runner делает import, запускает 13 focused и 4 real-process теста, проверяет exit
codes **и engine errors в логах**. Одна строка PASS при GDScript exception не
достаточна. `focused.json` содержит SHA256 логов. Существующие M6/M7 restart/replay
регрессии — обязательны; они не заменяют полный crash-in-async-write matrix.

## 2. Реальные GUI с Quaternius

Первый раз скопировать assets из ранее подтверждённого CHAR1-пакета. Пример пути
из Windows-отчёта; агент проверяет его наличие, а при другом расположении использует
фактический каталог `assets\external\quaternius`. Не копировать `.godot` другого
worktree. AssetSource применяется только при отсутствующем destination.

```powershell
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot `
    -AssetSource 'C:\dwsv-char1-git-hotfix-test\CHAR1_REALISTIC_WINDOWS_TEST\project\assets\external\quaternius' `
    -DurationSeconds 120 -WarmupSeconds 30 `
    -OutputDirectory "$WT\artifacts\net-smooth1\windows-gui-async"
$GuiExit = $LASTEXITCODE
```

Наличие fallback в GUI — ошибка. Runtime должен подтвердить real provider,
QUATERNIUS_RETARGET, отсутствие capsule, remote_count=1 для каждого клиента.
Headless с FALLBACK пригоден только для диагностики/функциональных проверок.

Стенд запускает server/A/B отдельными процессами с отдельными userdata/логами,
проверяет server world-ready и подключение, переключает обе камеры туда/обратно,
выполняет движение A/B/совместно, стрейф, повороты, бег, stop/start, затем reconnect B
вне performance window. Ввод идёт через принятый LIVE2 automation bridge — не через
прямое изменение позиции. Автотест не зависит от клавиатурного фокуса Windows.
В конце сохраняются viewport captures. Закрываются только созданные процессы.

## 3. Контролируемый A/B и отрицательный контроль

A/B использует **тот же код и trace**, меняя только periodic checkpoint mode;
это не выдаётся за полный historical CHAR2 baseline. Каждый запуск — свежий мир.
Остальные условия должны быть одинаковы. Повторить минимум три раза.

```powershell
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot -CheckpointMode sync `
    -DurationSeconds 120 -WarmupSeconds 30 `
    -OutputDirectory "$WT\artifacts\net-smooth1\windows-gui-sync"

.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot `
    -DurationSeconds 64 -WarmupSeconds 30 -InjectStallRole server -InjectStallMs 250 `
    -OutputDirectory "$WT\artifacts\net-smooth1\windows-negative-server-stall"
```

В negative контроль ожидается обнаруженный frame/server stall и **FAIL** (exit 1),
а не обычный PASS. INCONCLUSIVE не подтверждает работоспособность детектора.
Trace содержит явное событие injection. Аналогично проверить `-InjectStallRole a`.
Пороговые значения после результата не ослаблять. Стенд не доказывает нулевую
стоимость собственной инструментализации; её A/B с независимым frame capture
остаётся частью Windows performance review.

## 4. Длительный LOCAL-прогон

После устранения найденных FAIL выполнить:

```powershell
.\RUN_NET_SMOOTH1.ps1 -Mode gui -GodotConsole $Godot `
    -DurationSeconds 14400 -WarmupSeconds 60 `
    -OutputDirectory "$WT\artifacts\net-smooth1\windows-soak-4h"
```

Прогон превышает наблюдавшиеся 3.5 ч деградации. В конце проверяется reconnect на
долгоживущем сервере. Периодический late join третьего клиента, crash/restart в
середине записи и WAN matrix пока не автоматизированы этим runner. Не отмечать
их PASS на основании четырёхчасового движения двух клиентов.

`-Scenario local` ограничивает боковую траекторию primary-region. Отдельный
`-Scenario seam-stress` сохраняет более длинные перемещения: ранний exploratory
Linux-прогон воспроизвёл `USER1_SEAM_JOIN_FROZEN_WHILE_PLAYER_REMOTE` на reconnect,
когда другой игрок оставался на remote authority. Этот результат не устранять
отключением seam в продукте и не считать LAN packet loss. Исправление/приёмка
данного контракта — отдельный repair. `main` не закрывать, пока значимые findings
не получили отдельного решения.

## Артефакты и verdict

- `manifest.json`: HEAD/TREE, dirty flag, Godot SHA/version, asset manifest hash,
  CPU/OS/session, процессные ID, порты, параметры и exit codes; token скрыт.
- `server|a|b/trace.jsonl`: monotonic times **конкретного процесса**, header/END,
  frame intervals, server stages/messages, checkpoint capture/build/write,
  snapshot arrival, reconcile cost/correction, remote planar visual position/yaw.
- `phases.jsonl`, `avatar-status.json`, `initial-state.json`, `final-state.json`,
  captures, runtime logs, `report.json`, `report.md`.

Очередь trace ограничена 8192 записями, файл каждого процесса — 1 GiB; serializing
и запись выполняет постоянный worker. Overflow, IO failure, неверный run_id,
пропуск n, отсутствие END/measurement coverage/движения => INCONCLUSIVE, не PASS.
Для больших прогонов следить за указанным лимитом: при его исчерпании нужен новый
проектный slice ротации с непрерывной доказуемой последовательностью, не усечение
данных ради зелёного verdict.

`0=PASS` означает только пройденные измеренные критерии этого сценария;
`1=FAIL`; `2=INCONCLUSIVE`. `DIAGNOSTIC_ONLY` не является Windows GUI acceptance.
`GUI_LOCAL_CANDIDATE` не является independent VERIFIED. Fallback, несвежие traces,
неисполненная часть матрицы, пропуски логов не должны повышать статус.

Отчёт агенту: exact HEAD/TREE + Godot SHA; focused/17, analyzer; GUI/negative/A-B;
p99/p99.9/max кадра отдельно A/B/server; tick Hz и dropped time; capture/replay/
writer cost; ошибки и переходы NX5; resource/replay/recovery findings; ссылки на
артефакты. Сначала свежий reviewer/verifier, затем отдельное решение о merge.
